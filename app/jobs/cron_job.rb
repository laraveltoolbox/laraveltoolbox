# frozen_string_literal: true

#
# Invoked hourly via sidekiq-scheduler (see config/sidekiq.yml) to trigger
# recurring jobs based on the current time via the Cron service
#
class CronJob < ApplicationJob
  # The recurring jobs this dispatches are on the priority queue already, which
  # does them no good while the dispatcher itself waits behind the default
  # queue: a package sync fills that queue with tens of thousands of jobs, and
  # every hourly tick behind them is held up for as long as it takes to drain.
  # That includes the weekly download snapshot, which does nothing at all if it
  # is executed on a day that is no longer sunday.
  sidekiq_options queue: :priority

  def perform
    Cron.new.run
  end
end
