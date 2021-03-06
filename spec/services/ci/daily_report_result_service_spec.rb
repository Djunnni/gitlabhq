# frozen_string_literal: true

require 'spec_helper'

describe Ci::DailyReportResultService, '#execute' do
  let!(:pipeline) { create(:ci_pipeline, created_at: '2020-02-06 00:01:10') }
  let!(:rspec_job) { create(:ci_build, pipeline: pipeline, name: '3/3 rspec', coverage: 80) }
  let!(:karma_job) { create(:ci_build, pipeline: pipeline, name: '2/2 karma', coverage: 90) }
  let!(:extra_job) { create(:ci_build, pipeline: pipeline, name: 'extra', coverage: nil) }

  it 'creates daily code coverage record for each job in the pipeline that has coverage value' do
    described_class.new.execute(pipeline)

    Ci::DailyReportResult.find_by(title: 'rspec').tap do |coverage|
      expect(coverage).to have_attributes(
        project_id: pipeline.project.id,
        last_pipeline_id: pipeline.id,
        ref_path: pipeline.source_ref_path,
        param_type: 'coverage',
        title: rspec_job.group_name,
        value: rspec_job.coverage,
        date: pipeline.created_at.to_date
      )
    end

    Ci::DailyReportResult.find_by(title: 'karma').tap do |coverage|
      expect(coverage).to have_attributes(
        project_id: pipeline.project.id,
        last_pipeline_id: pipeline.id,
        ref_path: pipeline.source_ref_path,
        param_type: 'coverage',
        title: karma_job.group_name,
        value: karma_job.coverage,
        date: pipeline.created_at.to_date
      )
    end

    expect(Ci::DailyReportResult.find_by(title: 'extra')).to be_nil
  end

  context 'when there is an existing daily code coverage for the matching date, project, ref_path, and group name' do
    let!(:new_pipeline) do
      create(
        :ci_pipeline,
        project: pipeline.project,
        ref: pipeline.ref,
        created_at: '2020-02-06 00:02:20'
      )
    end
    let!(:new_rspec_job) { create(:ci_build, pipeline: new_pipeline, name: '4/4 rspec', coverage: 84) }
    let!(:new_karma_job) { create(:ci_build, pipeline: new_pipeline, name: '3/3 karma', coverage: 92) }

    before do
      # Create the existing daily code coverage records
      described_class.new.execute(pipeline)
    end

    it "updates the existing record's coverage value and last_pipeline_id" do
      rspec_coverage = Ci::DailyReportResult.find_by(title: 'rspec')
      karma_coverage = Ci::DailyReportResult.find_by(title: 'karma')

      # Bump up the coverage values
      described_class.new.execute(new_pipeline)

      rspec_coverage.reload
      karma_coverage.reload

      expect(rspec_coverage).to have_attributes(
        last_pipeline_id: new_pipeline.id,
        value: new_rspec_job.coverage
      )

      expect(karma_coverage).to have_attributes(
        last_pipeline_id: new_pipeline.id,
        value: new_karma_job.coverage
      )
    end
  end

  context 'when the ID of the pipeline is older than the last_pipeline_id' do
    let!(:new_pipeline) do
      create(
        :ci_pipeline,
        project: pipeline.project,
        ref: pipeline.ref,
        created_at: '2020-02-06 00:02:20'
      )
    end
    let!(:new_rspec_job) { create(:ci_build, pipeline: new_pipeline, name: '4/4 rspec', coverage: 84) }
    let!(:new_karma_job) { create(:ci_build, pipeline: new_pipeline, name: '3/3 karma', coverage: 92) }

    before do
      # Create the existing daily code coverage records
      # but in this case, for the newer pipeline first.
      described_class.new.execute(new_pipeline)
    end

    it 'updates the existing daily code coverage records' do
      rspec_coverage = Ci::DailyReportResult.find_by(title: 'rspec')
      karma_coverage = Ci::DailyReportResult.find_by(title: 'karma')

      # Run another one but for the older pipeline.
      # This simulates the scenario wherein the success worker
      # of an older pipeline, for some network hiccup, was delayed
      # and only got executed right after the newer pipeline's success worker.
      # Ideally, we don't want to bump the coverage value with an older one
      # but given this can be a rare edge case and can be remedied by re-running
      # the pipeline we'll just let it be for now. In return, we are able to use
      # Rails 6 shiny new method, upsert_all, and simplify the code a lot.
      described_class.new.execute(pipeline)

      rspec_coverage.reload
      karma_coverage.reload

      expect(rspec_coverage).to have_attributes(
        last_pipeline_id: pipeline.id,
        value: rspec_job.coverage
      )

      expect(karma_coverage).to have_attributes(
        last_pipeline_id: pipeline.id,
        value: karma_job.coverage
      )
    end
  end

  context 'when pipeline has no builds with coverage' do
    let!(:new_pipeline) do
      create(
        :ci_pipeline,
        created_at: '2020-02-06 00:02:20'
      )
    end
    let!(:some_job) { create(:ci_build, pipeline: new_pipeline, name: 'foo') }

    it 'does nothing' do
      expect { described_class.new.execute(new_pipeline) }.not_to raise_error
    end
  end
end
