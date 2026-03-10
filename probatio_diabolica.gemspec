# frozen_string_literal: true

Gem::Specification.new do |spec|
  spec.name          = "probatio_diabolica"
  spec.version       = "0.1.0"
  spec.authors       = ["Votre Nom"]
  spec.email         = ["votre.email@example.com"]

  spec.summary       = "Une courte description de votre gem."
  spec.description   = "Une description plus détaillée de votre gem."
  spec.homepage      = "https://example.com/llm_spec"
  spec.license       = "MIT"

  spec.files         = Dir["lib/**/*.rb", "README.md"]
  spec.bindir        = "bin"
  spec.executables << "prd"
  spec.require_paths = ["lib"]

  spec.add_dependency "ruby_llm"
  spec.add_dependency 'ruby_llm-schema'
  spec.add_dependency 'prawn'
  spec.add_dependency 'prism'
  spec.add_dependency 'zeitwerk'
end
