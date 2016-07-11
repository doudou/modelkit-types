module ModelKit::Types
    module Models
        module CompoundType
            include Type

            class Field
                attr_reader :index
                attr_reader :compound
                attr_reader :name
                attr_reader :type
                attr_accessor :offset
                attr_accessor :skip

                def metadata; @metadata ||= MetaData.new end

                def has_metadata?; @metadata && !@metadata.empty? end

                def initialize(compound, index, name, type, offset: nil, skip: 0)
                    @compound, @index, @name, @type, @offset, @skip = compound, index, name, type, offset, skip
                    # We create the metadata only if needed
                    @metadata = nil
                end

                def size
                    type.size + skip
                end

                def validate_merge(field)
                    if field.name != name
                        raise ArgumentError, "invalid field passed to #merge: name mismatches"
                    end

                    # See documentation of {Type#merge} for an explanation about
                    # why we don't test #type completely but only on name
                    if field.type.name != type.name
                        raise MismatchingFieldTypeError, "field #{name} from #{compound} has a type named #{type.name} but the correspondinf field in #{field.compound} has a type named #{field.type.name}"
                    end
                end

                def merge(field)
                    if field.has_metadata?
                        metadata.merge(field.metadata)
                    end
                    self
                end
            end

            def self.extend_object(obj)
                super
                obj.name = "ModelKit::Types::CompoundType"
            end

            def initial_buffer_size
                if @initial_buffer_size
                    @initial_buffer_size
                end
                @initial_buffer_size = each.inject(0) do |s, field|
                    s + field.type.initial_buffer_size + field.skip
                end
            end

            def buffer_size_at(buffer, offset)
                if fixed_buffer_size?
                    return size
                else
                    each.inject(0) do |current_offset, field|
                        current_offset + field.type.buffer_size_at(buffer, offset + current_offset) +
                            field.skip
                    end
                end
            end

            def ==(other)
                return true if self.equal?(other)
                return false if !super

                if fields_by_index.size != other.fields_by_index.size
                    return false
                end

                self_offset, other_offset = 0, 0
                fields_by_index.zip(other.fields_by_index) do |self_field, other_field|
                    if self_offset != other_offset
                        return false
                    elsif self_field.name != other_field.name
                        return false
                    elsif self_field.type != other_field.type
                        return false
                    end

                    self_offset += self_field.size
                    other_offset += other_field.size
                end
                true
            end

            def casts_to?(type)
                if super
                    true
                elsif field = fields_by_index.first
                    field.type.casts_to?(type)
                end
            end

            # Called by the extension to initialize the subclass
            # For each field, it creates getters and setters on 
            # the object, and a getter in the singleton class 
            # which returns the field type
            def setup_submodel(submodel, registry: self.registry, typename: nil, size: 0, opaque: false, null: false, &block)
                super

                submodel.instance_variable_set(:@fields_by_index, Array.new)
                submodel.instance_variable_set(:@fields_by_name, Hash.new)
                submodel.instance_variable_set(:@next_offset, 0)
                submodel.instance_variable_set(:@initial_buffer_size, nil)
                super
            end

            def copy_to(registry, **options)
                model = super
                fields_by_name.each do |field_name, field|
                    field_type =
                        if existing_field_t = registry.find_by_name(field.type.name) 
                            existing_field_t
                        else field.type.copy_to(registry)
                        end

                    new_field = model.add(field_name, field_type, skip: field.skip)
                    new_field.metadata.merge(field.metadata)
                end
                model
            end

            # The fields organized in order
            #
            # @return [Array<Field>]
            attr_reader :fields_by_index

            # The fields organized by name
            #
            # @return [Hash<String,Field>]
            attr_reader :fields_by_name

            # Adds a field to this type
            def add(name, type, skip: 0, offset: nil)
                name = name.to_str
                if fields_by_name[name]
                    raise DuplicateFieldError, "#{self} already has a field called #{name}"
                elsif type.respond_to?(:to_str)
                    type = registry.build(type)
                elsif type.registry != registry
                    raise NotFromThisRegistryError, "#{type} is from #{type.registry} and #{self} is from #{registry}, cannot add a field"
                end

                add_direct_dependency(type)

                if fields_by_index.empty? && offset && offset != 0
                    raise ArgumentError, "first field of a compounds must be at offset 0"
                elsif offset
                    last_field = fields_by_index.last
                    # Update the skip for the last field
                    #
                    # Variable sized buffers are always marshalled without skips
                    if last_field && last_field.type.fixed_buffer_size?
                        if (last_field.skip != 0)
                            if (@next_offset != offset)
                                raise ArgumentError, "offset explicitely provided for new field #{name} (#{offset}) does not match what would have been expected by previous offset/skips (#{@next_offset})"
                            end
                        else
                            last_field.skip = offset - @next_offset
                        end
                    end
                else
                    offset = @next_offset
                end
                @next_offset = offset + type.size + skip

                field = Field.new(self, fields_by_index.size, name, type, offset: offset, skip: skip)
                fields_by_index << field
                fields_by_name[name] = field
                self.contains_opaques = self.contains_opaques? || type.contains_opaques? || type.opaque?
                self.fixed_buffer_size = self.fixed_buffer_size? && type.fixed_buffer_size?
                field
            end

            # Returns true if this compound has no fields
            def empty?
                fields_by_name.empty?
            end

            # Returns the type of the expected field
            def [](name)
                get(name).type
            end

            # Returns the n-th field
            def field_at(index)
            end

            # Accesses a field by name
            #
            # @param [#to_str] name the field name
            # @return [Field]
            # @raise [FieldNotFound] if there are no fields with this name
            def get(name)
                name = name.to_str
                if result = fields_by_name[name]
                    result
                else
                    raise FieldNotFound, "#{name} is not a field of #{self} (fields are #{fields_by_name.keys.join(", ")})"
                end
            end

            # True if the given field is defined
            def has_field?(name)
                fields_by_name.has_key?(name.to_str)
            end

            # Enumerates the compound's fields
            #
            # @yieldparam [Field] field
            def each(&block)
                fields_by_name.each_value(&block)
            end

            # Returns the description of a type using only simple ruby objects
            # (Hash, Array, Numeric and String).
            # 
            #    { 'name' => TypeName,
            #      'class' => NameOfTypeClass, # CompoundType, ...
            #       # The content of 'element' is controlled by the :recursive option
            #      'fields' => [{ 'name' => FieldName,
            #                     # the 'type' field is controlled by the
            #                     # 'recursive' option
            #                     'type' => FieldType,
            #                     # 'offset' is present only if :layout_info is
            #                     # true
            #                     'offset' => FieldOffsetInBytes
            #                   }],
            #      'size' => SizeOfTypeInBytes # Only if :layout_info is true
            #    }
            #
            # @option (see Type#to_h)
            # @return (see Type#to_h)
            def to_h(options = Hash.new)
                fields = Array.new
                if options[:recursive]
                    each.map do |field|
                        fields << Hash[name: field.name, type: field.type.to_h(options), offset: field.offset]
                    end
                else
                    each.map do |field|
                        fields << Hash[name: field.name, type: field.type.to_h_minimal(options), offset: field.offset]
                    end
                end

                if !options[:layout_info]
                    fields.each { |f| f.delete(:offset) }
                end
                super.merge(fields: fields)
            end

            def validate_merge(type)
                super

                type_fields = type.fields_by_index
                self_fields = fields_by_index
                if type_fields.size != self_fields.size
                    raise MismatchingFieldSetError, "#{self} and #{type} have different number of fields"
                end

                type_offset, self_offset = 0, 0
                type_fields.zip(self_fields) do |type_f, self_f|
                    if type_offset != self_offset
                        raise MismatchingFieldOffsetError, "#{type_f.name} is at offset #{type_offset} in #{type} and at offset #{self_offset} in #{self}"
                    end
                    type_f.validate_merge(self_f)
                    type_offset += type_f.size
                    self_offset += self_f.size
                end
            end

            def merge(type)
                super
                each do |f|
                    f.merge(type.get(f.name))
                end
                self
            end

            def pretty_print_common(pp) # :nodoc:
                pp.group(2, '{', '}') do
                    pp.breakable

                    pp.seplist(each.to_a) do |field|
                        yield(*field)
                    end
                end
            end

            def pretty_print(pp, verbose: false) # :nodoc:
                super(pp)
                pp.text ' '
                pretty_print_common(pp) do |field|
                    if doc = field.metadata.get('doc').first
                        if pp_doc(pp, doc)
                            pp.breakable
                        end
                    end
                    pp.text field.name
                    pp.text " <"
                    pp.nest(2) do
                        field.type.pretty_print(pp, verbose: false)
                    end
                    pp.text '>'
                end
            end

            # Apply a set of type-to-size mappings
            #
            # @return [Integer,nil] the type's new size if it needs to be resized
            def apply_resize(typemap)
                fields = self.fields_by_name.values.sort_by { |f| f.offset }
                fields.inject(0) do |min_offset, f|
                    if f.offset < min_offset
                        f.offset = min_offset
                    end
                    f.offset + typemap[f.type]
                end
            end
        end
    end
end

