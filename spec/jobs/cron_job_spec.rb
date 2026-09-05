# frozen_string_literal: true

require "rails_helper"

RSpec.describe CronJob do
  let(:job) { described_class.new }

  describe "#perform" do
    it "runs the Cron service" do
      cron = instance_double(Cron)
      allow(Cron).to receive(:new).and_return(cron)
      expect(cron).to receive(:run)

      job.perform
    end
  end

  #
  # The recurring jobs it dispatches are on the priority queue, which is no
  # help while the dispatcher waits behind a default queue holding a package
  # sync's tens of thousands of jobs
  #
  it "runs on the priority queue so a backlog cannot hold up the schedule" do
    expect(described_class.get_sidekiq_options["queue"].to_s).to eq "priority"
  end

  describe "schedule" do
    let(:config) { YAML.load ERB.new(Rails.root.join("config", "sidekiq.yml").read).result }
    let(:schedule) { config[:scheduler][:schedule] }

    it "is registered in the sidekiq-scheduler config" do
      expect(schedule.dig("cron", "class").constantize).to eq described_class
    end

    it "is scheduled hourly" do
      expect(schedule.dig("cron", "cron")).to eq "0 * * * *"
    end
  end
end
