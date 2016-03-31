module ModelKit::Types
    # Base class for compound types (structs, unions)
    #
    # See the ModelKit::Types module documentation for an overview about how types are
    # values are represented.
    class CompoundType < Type
        extend Models::CompoundType

	# Initializes this object to the pointer +ptr+, and initializes it
	# to +init+. Valid values for +init+ are:
	# * a hash, in which case it is a { field_name => field_value } hash
	# * an array, in which case the fields are initialized in order
	# Note that a compound should be either fully initialized or not initialized
        def initialize_subtype
            super
            @__raw_fields = Hash.new
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
                ModelKit::Types.to_ruby(@fields[name], @field_types[name])
            else
                value = typelib_get_field(name.to_s, false)
                if value.kind_of?(ModelKit::Types::Type)
                    @fields[name] = value
                    ModelKit::Types.to_ruby(value, @field_types[name])
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
                if attribute.kind_of?(ModelKit::Types::Type)
                    return ModelKit::Types.copy(attribute, value)
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

            value = ModelKit::Types.from_ruby(value, @field_types[name])
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
