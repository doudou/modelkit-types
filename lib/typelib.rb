# Backward-compatible wrapping of the TypeStore API to mimick the Typelib API
require 'typestore'
require 'typestore/cxx'
require 'typestore/io/idl_exporter'
module Typelib
    NotFound = TypeStore::NotFound

    Type = TypeStore::Type
    class Type
        def self.dependencies
            direct_dependencies
        end
    end

    ArrayType = TypeStore::ArrayType
    NumericType = TypeStore::NumericType
    ContainerType = TypeStore::ContainerType
    class ContainerType
        def self.container_kind
            container_model.name
        end
    end

    CompoundType = TypeStore::CompoundType
    class CompoundType
        def self.field_metadata
            each.inject(Hash.new) do |h, field|
                h[field.name] = field.metadata; h
            end
        end
    end

    IndirectType = TypeStore::IndirectType
    EnumType = TypeStore::EnumType
    class EnumType
        def self.keys
            symbol_to_value.keys
        end
    end
    OpaqueType = TypeStore::Type

    Registry = TypeStore::Registry
    class Registry
        def merge_xml(string)
            xml = REXML::Document.new(string)
            merge(TypeStore::IO::XMLImporter.new.from_xml(xml))
        end

        def to_xml
            TypeStore::IO::XMLExporter.new.to_xml(self).to_s
        end

        def alias(new_name, old_type)
            create_alias(new_name, old_type)
        end
    end

    def self.specialize_model(*args, **options, &block)
        TypeStore.specialize_model(*args, **options, &block)
    end

    def self.specialize(*args, **options, &block)
        TypeStore.specialize(*args, **options, &block)
    end

    def self.convert_to_ruby(*args, **options, &block)
        TypeStore.convert_to_ruby(*args, **options, &block)
    end

    def self.convert_from_ruby(*args, **options, &block)
        TypeStore.convert_from_ruby(*args, **options, &block)
    end

    CXXRegistry = TypeStore::CXX::Registry

    CXX = TypeStore::CXX

    def self.namespace(name)
        TypeStore.namespace(name)
    end

    def self.basename(name)
        TypeStore.basename(name)
    end

    def self.split_typename(name)
        TypeStore.typename_parts(name)
    end

    def self.load_type_plugins?
        TypeStore.warn "load_type_plugins? is deprecated, you have to call Typelib.load_plugins explicitely now"
        false
    end

    def self.load_type_plugins=(flag)
        TypeStore.warn "load_type_plugins= is deprecated, you have to call Typelib.load_plugins explicitely now"
    end

    def self.load_typelib_plugins
        TypeStore.load_plugins
    end

    module CXX
        def self.preprocess(toplevel_files, kind, options)
            require 'typestore/io/cxx_importer'
            TypeStore::IO::CXXImporter.preprocess(toplevel_files, options)
        end
    end
end

