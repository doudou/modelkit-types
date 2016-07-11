module ModelKit::Types
    # Base class for compound types (structs, unions)
    #
    # See the ModelKit::Types module documentation for an overview about how types are
    # values are represented.
    class CompoundType < Type
        extend Models::CompoundType

        # The per-index field definitions
        attr_reader :__fields
        # The computed field offsets
        attr_reader :__field_offsets
        # The cached field values
        attr_reader :__field_values
        # The field types, offste and size on a per-name basis
        attr_reader :__field_type_offset_and_size

        def initialize_subtype
            super
            @__fields  = self.class.fields_by_index
        end

        # Reinitialize cached values when resetting the underlying buffer
        def reset_buffer(buffer)
            super
            @__field_offsets = Array.new(__fields.size + 1)
            @__field_offsets[0]  = 0
            @__field_offsets[-1] = self.class.initial_buffer_size
            @__field_type_offset_and_size = Hash.new
            @__field_values = Hash.new
        end

        # Sets this value's contents from a hash
        def from_ruby(value)
            value.each do |field_name, field_value|
                get(field_name.to_s).from_ruby(field_value)
            end
        end

        def apply_changes
            return if self.class.fixed_buffer_size?

            variable_sized_fields = Array.new
            self.class.each do |field|
                if !field.type.fixed_buffer_size? && (field_value = __field_values[field.name])
                    variable_sized_fields << [field, field_value]
                end
            end

            buffer = ""
            current_offset = 0
            variable_sized_fields.sort_by { |f, _| f.offset }.
                each do |field, field_value|
                    _field_type, orig_field_offset, orig_field_size = __field_type_offset_and_size[field.name]
                    buffer.concat(__buffer[current_offset, orig_field_offset])
                    buffer.concat(field_value.to_byte_array)
                    buffer.concat("\x0" * field.skip)
                    current_offset = orig_field_offset + orig_field_size + field.skip
                end

            buffer.concat(__buffer[current_offset, __buffer.size - current_offset])
            reset_buffer(Buffer.new(buffer))
        end

        # Returns the type, offset and size of a field in the marshalled data
        def __type_offset_and_size(name)
            if result = __field_type_offset_and_size[name]
                return *result
            end

            field, offset, next_offset = nil
            __fields.size.times do |field_index|
                field = __fields[field_index]
                offset           = __field_offsets[field_index]
                next_offset      = __field_offsets[field_index + 1]
                if !next_offset
                    field_skip = field.skip
                    field_size = field.type.buffer_size_at(__buffer, offset)
                    next_offset = offset + field_size + field_skip
                    __field_offsets[field_index + 1] = next_offset
                end

                if field.name == name
                    return (__field_type_offset_and_size[name] = [field.type, offset, next_offset - offset - field.skip])
                end
            end
            raise ArgumentError, "#{self} has no field named #{name}"
        end

        # Enumerate this compound fields
        #
        # @yieldparam [String] name the field name
        # @yieldparam [Type] value the field value
        def each_field
            return enum_for(__method__) if !block_given?

            self.class.each do |field|
                yield(field.name, get(field.name))
            end
        end

        def pretty_print(pp) # :nodoc:
            pp.text "{"
            pp.nest(2) do
                pp.breakable
                pp.seplist(each_field) do |name, value|
                    pp.text name
                    pp.text " = "
                    value.pretty_print(pp)
                end
            end
            pp.breakable
            pp.text "}"
        end

        # Returns true if +name+ is a valid field name. It can either be given
        # as a string or a symbol
        def has_field?(name)
            self.class.has_field?(name)
        end

        # Returns the value of the given field
        def [](name)
            get(name)
        end

        # Returns the value of the given field
        def get(name)
            if value = @__field_values[name]
                value
            else
                type, offset, size = __type_offset_and_size(name)
                buffer_slice = __buffer.view(offset, size)
                if type.fixed_buffer_size?
                    @__field_values[name] = type.wrap!(buffer_slice)
                else
                    @__field_values[name] = type.from_buffer!(buffer_slice)
                end
            end
        end

        # Set the value of a field
        def set(name, value)
            value.copy_to(get(name))
        end

        # Sets the value of a field
        def []=(name, value)
            set(name, value)
        end

        # Converts this value into a plain Ruby representation
        def to_ruby
            result = Hash.new
            each_field { |name, v| result[name.to_s] = v.to_ruby }
            result
        end

        # (see Type#to_simple_value)
        #
        # Compound types are returned as a hash from the field name (as a
        # string) to the converted field value.
        def to_simple_value(**options)
            result = Hash.new
            each_field { |name, v| result[name.to_s] = v.to_simple_value(**options) }
            result
        end
    end
end

