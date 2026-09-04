# frozen_string_literal: true

#
# This basic utility class is used for running recurring tasks
# based on the current time. It is meant to be invoked once per
# hour via the sidekiq-scheduler-managed CronJob (see config/sidekiq.yml),
# or manually using `rake cron`
#
class Cron
  def run(time: Time.current.utc)
    run_scheduled time.hour
    run_hourly
  rescue StandardError => e
    Appsignal.set_error e
    raise e
  end

  private

  # The jobs that only run at certain hours of the day
  def run_scheduled(hour)
    PackagesSyncJob.perform_async if hour.zero? || empty_mirror?
    PackageAdvisoriesSyncJob.perform_async if hour == 3
    Database::StoreSelectiveExportJob.perform_async if (hour % 4).zero?
  end

  def run_hourly
    PackageDownloadsPersistenceJob.perform_async
    RemoteUpdateSchedulerJob.perform_async
    CatalogImportJob.perform_async
    GithubIgnore.expire!
  end

  #
  # Everything here other than the nightly packagist sync only ever refreshes
  # packages that are mirrored already, so a freshly deployed instance has
  # nothing to work from and would sit empty until the next midnight. An empty
  # mirror therefore kicks the sync off on the next hourly tick instead.
  #
  def empty_mirror?
    !Package.exists?
  end
end
