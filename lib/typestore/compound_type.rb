module TypeStore
    # Base class for compound types (structs, unions)
    #
    # See the TypeStore module documentation for an overview about how types are
    # values are represented.
    class CompoundType < Type
        extend Models::CompoundType

        module CustomConvertionsHandling
            def invalidate_changes_from_converted_types
                super()
                self.class.converted_fields.each do |field_name|
                    instance_variable_set("@#{field_name}", nil)
                    if @fields[field_name]
                        @fields[field_name].invalidate_changes_from_converted_types
                    end
                end
            end

            def apply_changes_from_converted_types
                super()
                self.class.converted_fields.each do |field_name|
                    value = instance_variable_get("@#{field_name}")
                    if !value.nil?
                        if @fields[field_name]
                            @fields[field_name].apply_changes_from_converted_types
                        end
                        set_field(field_name, value)
                    end
                end
            end

            def dup
                new_value = super()
                for field_name in self.class.converted_fields
                    converted_value = instance_variable_get("@#{field_name}")
                    if !converted_value.nil?
                        # false, nil,  numbers can't be dup'ed
                        if !DUP_FORBIDDEN.include?(converted_value.class)
                            converted_value = converted_value.dup
                        end
                        instance_variable_set("@#{field_name}", converted_value)
                    end
                end
                new_value
            end
        end

        # Internal method used to initialize a compound from a hash
        def set_hash(hash) # :nodoc:
            hash.each do |field_name, field_value|
                set_field(field_name, field_value)
            end
        end

        # Internal method used to initialize a compound from an array. The array
        # elements are supposed to be given in the field order
        def set_array(array) # :nodoc:
            fields = self.class.fields
            array.each_with_index do |value, i|
                set_field(fields[i][0], value)
            end
        end

	# Initializes this object to the pointer +ptr+, and initializes it
	# to +init+. Valid values for +init+ are:
	# * a hash, in which case it is a { field_name => field_value } hash
	# * an array, in which case the fields are initialized in order
	# Note that a compound should be either fully initialized or not initialized
        def typestore_initialize
            super
	    # A hash in which we cache Type objects for each of the structure fields
	    @fields = Hash.new
            @field_types = self.class.field_types
        end

        def raw_each_field
            return enum_for(__method__) if !block_given?
            self.class.each_field do |field_name, _|
                yield(field_name, raw_get(field_name))
            end
        end

        def each_field
            return enum_for(__method__) if !block_given?
            self.class.each_field do |field_name, _|
                yield(field_name, get(field_name))
            end
        end

	def pretty_print(pp) # :nodoc:
            apply_changes_from_converted_types
	    self.class.pretty_print_common(pp) do |name, offset, type|
		pp.text name
		pp.text "="
		get_field(name).pretty_print(pp)
	    end
	end

        # Returns true if +name+ is a valid field name. It can either be given
        # as a string or a symbol
        def has_field?(name)
            @field_types.has_key?(name)
        end

        def [](name)
            get(name)
        end

	# Returns the value of the field +name+
        def get_field(name)
            get(name)
	end

        def raw_get_field(name)
            raw_get(name)
        end


        def get(name)
            if @fields[name]
                TypeStore.to_ruby(@fields[name], @field_types[name])
            else
                value = typelib_get_field(name.to_s, false)
                if value.kind_of?(TypeStore::Type)
                    @fields[name] = value
                    TypeStore.to_ruby(value, @field_types[name])
                else value
                end
            end
        end

        def raw_get(name)
            @fields[name] ||= typelib_get_field(name, true)
        end

        def raw_get_cached(name)
            @fields[name]
        end

        def raw_set_field(name, value)
            raw_set(name, value)
        end

        def raw_set(name, value)
            if value.kind_of?(Type)
                attribute = raw_get(name)
                # If +value+ is already a typelib value, just do a plain copy
                if attribute.kind_of?(TypeStore::Type)
                    return TypeStore.copy(attribute, value)
                end
            end
            typelib_set_field(name, value)

	rescue ArgumentError => e
	    if e.message =~ /^no field \w+ in /
		raise e, (e.message + " in #{name}(#{self.class.name})"), e.backtrace
	    else
		raise e, (e.message + " while setting #{name} in #{self.class.name}"), e.backtrace
	    end
        end

        def set_field(name, value)
            set(name, value)
        end

        def []=(name, value)
            set(name, value)
        end

        # Sets the value of the field +name+. If +value+ is a hash, we expect
        # that the field is a compound type and initialize it using the keys of
        # +value+ as field names
        def set(name, value)
            if !has_field?(name)
                raise ArgumentError, "#{self.class.name} has no field called #{name}"
            end

            value = TypeStore.from_ruby(value, @field_types[name])
            raw_set_field(name.to_s, value)

	rescue TypeError => e
	    raise e, "#{e.message} for #{self.class.name}.#{name}", e.backtrace
	end

        # (see Type#to_simple_value)
        #
        # Compound types are returned as a hash from the field name (as a
        # string) to the converted field value.
        def to_simple_value(options = Hash.new)
            result = Hash.new
            raw_each_field { |name, v| result[name.to_s] = v.to_simple_value(options) }
            result
        end
    end
end
