require 'modelkit/types'
require 'modelkit/types/cxx'

module ModelKit::Types
    class Type
        def to_csv
            ModelKit::Types::IO::CSV.export(self)
        end

        def from_buffer_direct(buffer)
            reset_buffer(buffer.to_types_buffer)
        end
    end

    class ArrayType
        def raw_get(i)
            get(i)
        end

        def raw_each(&block)
            each(&block)
        end
    end

    class CompoundType
        def raw_get(i)
            get(i)
        end
    end

    class ContainerType
        def raw_get(i)
            get(i)
        end

        def raw_each(&block)
            each(&block)
        end
    end

    module Models
        module Type
            def to_csv(prefix = "")
                ModelKit::Types::IO::CSV.flatten_type(self).map { |desc| "#{prefix}#{desc}" }.join(",")
            end
        end

        module CompoundType
            def each_field
                each do |field|
                    yield(field.name, field.type)
                end
            end
        end

        module EnumType
            def keys
                symbol_to_value
            end
        end
    end
end

module Typelib
    def self.load_type_plugins=(flag)
    end

    class Registry < ModelKit::Types::Registry
        def initialize
            super
            register_container_model ModelKit::Types::CXX::StdVector
            register_container_model ModelKit::Types::CXX::BasicString
        end

        def create_numeric(name, size = nil, kind = nil, **options)
            if !options.empty?
                super(name, **options)
            elsif kind == :sint
                super(name, size: size, integer: true, unsigned: false)
            elsif kind == :uint
                super(name, size: size, integer: true, unsigned: true)
            elsif kind == :float
                super(name, size: size, integer: false)
            else
                raise ArgumentError, "expected numeric category to be one of :sint, :uint or :float"
            end
        end

        def to_xml
            ModelKit::Types::IO::XMLExporter.export(self)
        end
    end

    Type = ModelKit::Types::Type
    NumericType = ModelKit::Types::NumericType
    ArrayType = ModelKit::Types::ArrayType
    EnumType = ModelKit::Types::EnumType
    IndirectType = ModelKit::Types::IndirectType
    ContainerType = ModelKit::Types::ContainerType
    CompoundType = ModelKit::Types::CompoundType

    def self.copy(target, source)
        source.copy_to(target)
    end

    def self.from_ruby(value, type)
        if value.class == type
            value
        else
            type.from_ruby(value)
        end
    end

    def self.to_ruby(value)
        value.to_ruby
    end
end

