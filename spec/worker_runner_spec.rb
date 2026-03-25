require 'tmpdir'
require 'stringio'

def with_temp_specs_dir
  Dir.mktmpdir('prd_worker_runner') do |dir|
    yield dir
  end
end

def render_simple_synthetic(model)
  io = StringIO.new
  formatter = PrD::Formatters::SimpleFormatter.new(io: io, mode: :synthetic)
  PrD::ReportRenderer.render(model, formatter)
  io.rewind
  io.read
end

describe 'PrD worker runner' do
  it 'produces deterministic file-order rendering with multiple workers' do
    with_temp_specs_dir do |dir|
      File.write(File.join(dir, 'a_spec.rb'), <<~SPEC)
        describe 'A suite' do
          it 'from a file' do
            sleep 0.2
            expect(1).to(eq(1))
          end
        end
      SPEC
      File.write(File.join(dir, 'b_spec.rb'), <<~SPEC)
        describe 'B suite' do
          it 'from b file' do
            expect(1).to(eq(1))
          end
        end
      SPEC

      file_paths = Dir[File.join(dir, '*_spec.rb')].sort
      result = PrD::WorkerRunner.new(
        file_paths: file_paths,
        jobs: 2,
        mode: :synthetic,
        serializers: {},
        output_dir: nil,
        config_file: nil,
        subject_display_strategy: :on_evaluation,
        eager_subject_display_strategy: :on_definition
      ).run

      output = render_simple_synthetic(result.model)
      expect(result.passed_count).to(eq(2))
      expect(result.failed_count).to(eq(0))
      expect(output.index('PASS: from a file') < output.index('PASS: from b file')).to(eq(true))
    end
  end

  it 'keeps same summary between jobs 1 and jobs 2' do
    with_temp_specs_dir do |dir|
      File.write(File.join(dir, 'a_spec.rb'), <<~SPEC)
        describe 'A suite' do
          it 'passes' do
            expect(1).to(eq(1))
          end
        end
      SPEC
      File.write(File.join(dir, 'b_spec.rb'), <<~SPEC)
        describe 'B suite' do
          it 'fails' do
            expect(1).to(eq(2))
          end
        end
      SPEC

      file_paths = Dir[File.join(dir, '*_spec.rb')].sort
      common_options = {
        file_paths: file_paths,
        mode: :synthetic,
        serializers: {},
        output_dir: nil,
        config_file: nil,
        subject_display_strategy: :on_evaluation,
        eager_subject_display_strategy: :on_definition
      }

      result_jobs_1 = PrD::WorkerRunner.new(**common_options, jobs: 1).run
      result_jobs_2 = PrD::WorkerRunner.new(**common_options, jobs: 2).run

      expect(result_jobs_1.passed_count).to(eq(result_jobs_2.passed_count))
      expect(result_jobs_1.failed_count).to(eq(result_jobs_2.failed_count))
    end
  end
end
