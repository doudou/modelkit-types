# Backward-compatible wrapping of the ModelKit::Types API to mimick the Typelib API
require 'modelkit/types'
require 'modelkit/types/cxx'
require 'modelkit/types/io/idl_exporter'
module Typelib
    NotFound = ModelKit::Types::NotFound

    Type = ModelKit::Types::Type
    class Type
        def self.dependencies
            direct_dependencies
        end
    end

    ArrayType = ModelKit::Types::ArrayType
    NumericType = ModelKit::Types::NumericType
    ContainerType = ModelKit::Types::ContainerType
    class ContainerType
        def self.container_kind
            container_model.name
        end
    end

    CompoundType = ModelKit::Types::CompoundType
    class CompoundType
        def self.field_metadata
            each.inject(Hash.new) do |h, field|
                h[field.name] = field.metadata; h
            end
        end
    end

    IndirectType = ModelKit::Types::IndirectType
    EnumType = ModelKit::Types::EnumType
    class EnumType
        def self.keys
            symbol_to_value.keys
        end
    end
    OpaqueType = ModelKit::Types::Type

    Registry = ModelKit::Types::Registry
    class Registry
        def merge_xml(string)
            xml = REXML::Document.new(string)
            merge(ModelKit::Types::IO::XMLImporter.new.from_xml(xml))
        end

        def to_xml
            ModelKit::Types::IO::XMLExporter.new.to_xml(self).to_s
        end

        def alias(new_name, old_type)
            create_alias(new_name, old_type)
        end
    end

    def self.specialize_model(*args, **options, &block)
        ModelKit::Types.specialize_model(*args, **options, &block)
    end

    def self.specialize(*args, **options, &block)
        ModelKit::Types.specialize(*args, **options, &block)
    end

    def self.convert_to_ruby(*args, **options, &block)
        ModelKit::Types.convert_to_ruby(*args, **options, &block)
    end

    def self.convert_from_ruby(*args, **options, &block)
        ModelKit::Types.convert_from_ruby(*args, **options, &block)
    end

    CXXRegistry = ModelKit::Types::CXX::Registry

    CXX = ModelKit::Types::CXX

    def self.namespace(name)
        ModelKit::Types.namespace(name)
    end

    def self.basename(name)
        ModelKit::Types.basename(name)
    end

    def self.split_typename(name)
        ModelKit::Types.typename_parts(name)
    end

    def self.load_type_plugins?
        ModelKit::Types.warn "load_type_plugins? is deprecated, you have to call Typelib.load_plugins explicitely now"
        false
    end

    def self.load_type_plugins=(flag)
        ModelKit::Types.warn "load_type_plugins= is deprecated, you have to call Typelib.load_plugins explicitely now"
    end

    def self.load_typelib_plugins
        ModelKit::Types.load_plugins
    end

    module CXX
        def self.preprocess(toplevel_files, kind, options)
            require 'modelkit/types/io/cxx_importer'
            ModelKit::Types::IO::CXXImporter.preprocess(toplevel_files, options)
        end
    end
end

