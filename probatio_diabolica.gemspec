# frozen_string_literal: true

require_relative "lib/pr_d/version"

Gem::Specification.new do |spec|
  spec.name          = "probatio_diabolica"
  spec.version       = PrD::VERSION
  spec.authors       = ["Laporte Mathieu"]
  spec.email         = ["mathieu.laporte+prd@gmail.com"]

  spec.summary       = "A Ruby DSL testing framework with classic and LLM-powered matchers."
  spec.description   = "Probatio Diabolica runs custom *_spec.rb files with a DSL inspired by RSpec and supports text/image/PDF reporting."
  spec.homepage      = "https://github.com/syadem/probatio_diabolica"
  spec.license       = "MIT"
  spec.required_ruby_version = ">= 3.1"

  spec.metadata = {
    "source_code_uri" => "https://github.com/syadem/probatio_diabolica",
    "changelog_uri" => "https://github.com/syadem/probatio_diabolica/releases"
  }

  spec.files = Dir[
    "lib/**/*.rb",
    "bin/prd",
    "README.md",
    "Gemfile",
    "probatio_diabolica.gemspec"
  ]
  spec.bindir        = "bin"
  spec.executables << "prd"
  spec.require_paths = ["lib"]

  spec.add_dependency "ruby_llm"
  spec.add_dependency 'ruby_llm-schema'
  spec.add_dependency 'pdf-reader'
  spec.add_dependency 'prawn'
  spec.add_dependency 'zeitwerk'
end
