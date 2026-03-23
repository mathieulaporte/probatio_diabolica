module PrD
  module ReportRenderer
    module_function

    def render(model, formatter)
      model.events.each do |event|
        name = event.fetch(:name)
        args = event.fetch(:args)
        kwargs = event.fetch(:kwargs)
        if kwargs.empty?
          formatter.public_send(name, *args)
        else
          formatter.public_send(name, *args, **kwargs)
        end
      end
      formatter.flush
      formatter
    end
  end
end
