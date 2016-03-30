module ModelKit::Types
    module Models
        module ContainerType
            include IndirectType

            def self.extend_object(obj)
                super
                obj.name = "ModelKit::Types::ContainerType"
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

            # Whether this container has random-access capabilities
            def random_access?
                false
            end

            def setup_submodel(submodel, random_access: false, deference: nil, registry: self.registry, typename: nil, size: 0, opaque: false, null: false)
                super(submodel, deference: deference, registry: registry, typename: typename, size: size, opaque: opaque, null: null)

                submodel.fixed_buffer_size = false

                if random_access
                    submodel.include RandomAccessContainer
                end
            end

            def validate_merge(type)
                super

                if container_model != type.container_model
                    raise MismatchingContainerModel, "#{self} and #{type} are not from the same container model"
                end
            end

            def copy_to(registry, **options)
                if !registry.has_container_model?(container_model.name)
                    registry.register_container_model(container_model)
                end
                super(registry, random_access: random_access?, **options)
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

