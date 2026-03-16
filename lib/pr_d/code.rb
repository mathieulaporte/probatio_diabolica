module PrD
  class Code < SimpleDelegator
    attr_reader :source, :language

    def initialize(source:, language: 'ruby')
      super(source.to_s)
      @source = source.to_s
      @language = language.to_s
    end

    def to_s
      @source
    end

    def include?(value)
      @source.include?(value)
    end
  end
end
