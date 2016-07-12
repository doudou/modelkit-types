module ModelKit::Types
    module Models
        module ContainerType
            include IndirectType

            def self.extend_object(obj)
                super
                obj.name = "ModelKit::Types::ContainerType"
                obj.fixed_buffer_size = false
            end

            # The type of container
            #
            # The container hierarchy is different from the other types, as
            # there is always one class between {ContainerType} and the actual
            # container class. This class characterizes what type of container
            # it is
            def container_model
                supermodel
            end

            # @api private
            #
            # The size of a buffer when a new value is created with {#new}
            #
            # For containers, it is 8 bytes, that is the size of the element
            # containing the number of elements in the container
            def initial_buffer_size
                8
            end

            # @api private
            #
            # Returns the marshalled size of this container at the given point
            # in the buffer
            def buffer_size_at(buffer, offset)
                element_count = buffer[offset, 8].unpack("Q<").first
                if deference.fixed_buffer_size?
                    8 + element_count * deference.size
                else
                    access = ValueSequence.new(buffer.view(offset + 8), deference, element_count)
                    offset, size = access.offset_and_size_of(element_count - 1)
                    8 + offset + size
                end
            end

            # Whether this container has random-access capabilities
            def setup_submodel(submodel, deference: nil, registry: self.registry, typename: nil, size: 0, opaque: false, null: false)
                super(submodel, deference: deference, registry: registry, typename: typename, size: size, opaque: opaque, null: null)

                submodel.fixed_buffer_size = false
            end

            # @api private
            #
            # Validate that this type and the argument are equivalent. This is
            # used during registry merge
            #
            # @raise [InvalidMergeError]
            def validate_merge(type)
                if container_model != type.container_model
                    raise MismatchingContainerModel, "#{self} and #{type} are not from the same container model"
                end
                super
            end

            # Register a copy of this type in another registry
            #
            # @param (see IndirectType#copy_to)
            # @return [ContainerType]
            def copy_to(registry, **options)
                if !registry.has_container_model?(container_model.name)
                    registry.register_container_model(container_model)
                end
                super(registry, **options)
            end

            # Returns the description of a type using only simple ruby objects
            # (Hash, Array, Numeric and String).
            # 
            #    { name: TypeName,
            #      class: NameOfTypeClass, # CompoundType, ...
            #       # The content of 'element' is controlled by the :recursive option
            #      element: DescriptionOfArrayElement,
            #      size: SizeOfTypeInBytes # Only if :layout_info is true
            #    }
            #
            # @option (see Type#to_h)
            # @return (see Type#to_h)
            def to_h(options = Hash.new)
                info = super
                info[:kind] = info[:class]
                info[:class] = "ContainerType"
                if deference
                    info[:element] =
                        if options[:recursive]
                            deference.to_h(options)
                        else
                            deference.to_h_minimal(options)
                        end
                end
                info
            end
        end
    end
end

