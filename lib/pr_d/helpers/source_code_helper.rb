module PrD
  module Helpers
    module SourceCodeHelper
      def source_code(class_or_method)
        ensure_prism_loaded!

        if class_or_method.is_a?(Class)
          file, = Object.const_source_location(class_or_method.to_s)
          return nil unless file

          code = File.read(file)
          tree = Prism.parse(code)
          extract_class_from_node(tree.value, class_or_method.to_s, code)
        else
          file, line = class_or_method.source_location
          return nil unless file && line

          code = File.read(file)
          tree = Prism.parse(code)
          extract_method_from_node(tree.value, class_or_method.name, code)
        end
      end

      private

      def extract_method_from_node(node, method_name, code)
        return nil unless node.respond_to?(:child_nodes)

        node.child_nodes.each do |child|
          if child.is_a?(Prism::DefNode) && child.name.to_s == method_name.to_s
            return code[child.location.start_offset...child.location.end_offset]
          end

          found = extract_method_from_node(child, method_name, code)
          return found if found
        end

        nil
      end

      def extract_class_from_node(node, class_name, code)
        return nil unless node.respond_to?(:child_nodes)

        node.child_nodes.each do |child|
          if child.is_a?(Prism::ClassNode)
            path = child.constant_path&.slice
            return code[child.location.start_offset...child.location.end_offset] if path == class_name.to_s.split('::').last
          end

          found = extract_class_from_node(child, class_name, code)
          return found if found
        end

        nil
      end

      def ensure_prism_loaded!
        return if defined?(::Prism)

        require 'prism'
      rescue LoadError => e
        raise LoadError, "Source code helpers require the 'prism' gem. Install it with `gem install prism` or add `gem 'prism'` to your Gemfile. (#{e.message})"
      end
    end
  end
end
