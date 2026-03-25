require 'stringio'

module PrD
  class WorkerRunner
    RunResult = Struct.new(:model, :passed_count, :failed_count, keyword_init: true)
    WorkerResult = Struct.new(:model, :passed_count, :failed_count, keyword_init: true)

    def initialize(file_paths:, jobs:, mode:, serializers:, output_dir:, config_file:, subject_display_strategy:, eager_subject_display_strategy:)
      @file_paths = Array(file_paths)
      @jobs = jobs
      @mode = mode
      @serializers = serializers
      @output_dir = output_dir
      @config_file = config_file
      @subject_display_strategy = subject_display_strategy
      @eager_subject_display_strategy = eager_subject_display_strategy
    end

    def run
      raise ArgumentError, 'No spec files found to execute.' if @file_paths.empty?

      worker_count = [[@jobs, 1].max, @file_paths.length].min
      results = Array.new(@file_paths.length)
      mutex = Mutex.new
      next_index = 0
      first_error = nil

      workers = Array.new(worker_count) do
        Thread.new do
          loop do
            index, path = mutex.synchronize do
              break if next_index >= @file_paths.length

              current_index = next_index
              next_index += 1
              [current_index, @file_paths[current_index]]
            end
            break if index.nil?

            begin
              results[index] = run_file(path)
            rescue StandardError => e
              mutex.synchronize { first_error ||= e }
              break
            end
          end
        end
      end

      workers.each(&:join)
      raise first_error unless first_error.nil?

      merge_results(results)
    end

    private

    def run_file(path)
      collector = PrD::ReportCollector.new(
        io: StringIO.new,
        serializers: @serializers,
        mode: @mode,
        subject_display_strategy: @subject_display_strategy,
        eager_subject_display_strategy: @eager_subject_display_strategy
      )

      runtime = PrD::Runtime.new(formatter: collector, output_dir: @output_dir, config_file: @config_file)
      runtime.run([File.read(path)])

      WorkerResult.new(
        model: collector.model,
        passed_count: runtime.passed_count,
        failed_count: runtime.failed_count
      )
    end

    def merge_results(results)
      merged_model = PrD::ReportModel.new
      passed_count = 0
      failed_count = 0

      results.each do |result|
        passed_count += result.passed_count
        failed_count += result.failed_count

        result.model.events.each do |event|
          next if event[:name] == :result

          merged_model.add_event(
            name: event[:name],
            args: event[:args],
            kwargs: event[:kwargs]
          )
        end
      end

      merged_model.summary = { passed: passed_count, failed: failed_count }
      merged_model.add_event(name: :result, args: [passed_count, failed_count], kwargs: {})

      RunResult.new(model: merged_model, passed_count: passed_count, failed_count: failed_count)
    end
  end
end
