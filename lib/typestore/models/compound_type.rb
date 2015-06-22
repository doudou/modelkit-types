module TypeStore
    module Models
        module CompoundType
            include Type

            class Field
                attr_reader :name
                attr_reader :type

                def metadata; @metadata ||= MetaData.new end

                def initialize(name, type)
                    @name, @type = name, type
                end

                def offset
                    metadata.get('offset').first
                end
            end

            # @return [Hash<String,Field>] the set of fields composing this
            #   compound type
            attr_reader :fields

            # Check if a value of this type can be used in place of a value of
            # the given type
            #
            # In case of compound types, we check that either self, or the first
            # element field is of the requested type
	    def is_a?(type)
                super || (!fields.empty? && fields.each_value.find { |f| f.offset == 0 && f.type.is_a?(type) })
	    end

            # The set of fields that are converted to a different type when
            # accessed from Ruby, as a set of names
            attr_reader :converted_fields

            # Controls whether {#can_overload_method} should warn if some
            # overloading are not allowed, or be silent about it
            #
            # This is true by default
            attr_predicate :warn_about_helper_method_clashes?, true

            # Tests whether typestore should define some accessor methods for
            # the given field on self
            def can_define_field_accessor_methods?(reference, name,
                                     message: "instances of #{self.name}",
                                     allowed_overloadings: Models::Type::ALLOWED_OVERLOADINGS,
                                     with_raw: true,
                                     silent: !CompoundType.warn_about_helper_method_clashes?)

                candidates = [n, "#{n}="]
                if with_raw
                    candidates.concat(["raw_#{n}", "raw_#{n}="])
                end
                candidates.all? do |method_name|
                    if !reference.method_defined?(method_name) || allowed_overloadings.include?(method_name)
                        true
                    elsif !silent
                        TypeStore.warn "NOT defining #{candidates.join(", ")} on #{message} as it would overload a necessary method"
                        false
                    end
                end
            end

            # Adds a field to this type
            def add_field(name, type)
                if fields[name]
                    raise DuplicateFieldError.new(self, name), "#{self} already has a field called #{name}"
                end
                field = Field.new(name, type)
                fields[name] = field
                self.contains_opaques = self.contains_opaques? || type.contains_opaques?
                self.contains_converted_types = self.contains_converted_types? || type.contains_converted_types?
                if can_define_field_accessor_methods?(CompoundType, name)
                    define_raw_field_accessor_methods(name)
                    if type.contains_converted_types?
                        define_converted_field_accessor_methods(name)
                    else
                        define_plain_field_accessor_methods(name)
                    end
                end
                field
            end

            def define_raw_field_accessor_methods(name)
                define_method("raw_#{name}") do
                    @__typestore_raw_fields[name] ||= raw_get(name)
                end
                define_method("raw_#{name}=") do |value|
                    raw_set(name, value)
                end
            end

            def define_plain_field_accessor_methods(name)
                define_method(name) do
                    @__typestore_raw_fields[name] ||= raw_get(name)
                end
                define_method("#{name}=") do |value|
                    raw_set(name, value)
                end
            end

            def define_converted_field_accessor_methods(name, type, converter)
                define_method(name) do
                    (@__typestore_fields[name] ||= converter.to_ruby(raw_get(name)))
                end
                define_method("#{name}=") do |value|
                    if converted_field = @__typestore_fields[name]
                        converted_field
                    else
                        raw_set(name, type_from_ruby[value, type])
                        @__typestore_fields[name] = value
                    end
                end
            end

            @@custom_convertion_modules = Hash.new
            def custom_convertion_module(converted_fields)
                @@custom_convertion_modules[converted_fields] ||=
                    Module.new do
                        include CustomConvertionsHandling

                        converted_fields.each do |field_name|
                            attr_name = "@#{field_name}"
                            define_method("#{field_name}=") do |value|
                                instance_variable_set(attr_name, value)
                            end
                            define_method(field_name) do
                                v = instance_variable_get(attr_name)
                                if !v.nil?
                                    v
                                else
                                    v = get(field_name)
                                    instance_variable_set(attr_name, v)
                                end
                            end
                        end
                    end
            end

            # Creates a module that can be used to extend a certain Type class to
            # take into account the convertions.
            #
            # I.e. if a convertion is declared as
            #
            #   convert_to_ruby '/base/Time', :to => Time
            # 
            # and the type T is a structure with a field of type /base/Time, then
            # if
            #
            #   type = registry.get('T')
            #   type.extend_for_custom_convertions
            #
            # then
            #   t = type.new
            #   t.time => Time instance
            #   t.time => the same Time instance
            def extend_for_custom_convertions
                super if defined? super

                if !converted_fields.empty?
                    self.contains_converted_types = true
                    converted_fields = TypeStore.filter_methods_that_should_not_be_defined(
                        self, self, self.converted_fields, Type::ALLOWED_OVERLOADINGS, nil, false)

                    m = custom_convertion_module(converted_fields)
                    include(m)
                end
            end

            @@access_method_modules = Hash.new
            def access_method_module(full_fields_names, converted_field_names)
                @@access_method_modules[[full_fields_names, converted_field_names]] ||=
                    Module.new do
                        full_fields_names.each do |name|
                            define_method(name) { get(name) }
                            define_method("#{name}=") { |value| set(name, value) }
                            define_method("raw_#{name}") { raw_get(name) }
                            define_method("raw_#{name}=") { |value| raw_set(name, value) }
                        end
                        converted_field_names.each do |name|
                            define_method("raw_#{name}") { raw_get(name) }
                            define_method("raw_#{name}=") { |value| raw_set(name, value) }
                        end
                    end
            end

	    # Called by the extension to initialize the subclass
	    # For each field, it creates getters and setters on 
	    # the object, and a getter in the singleton class 
	    # which returns the field type
            def setup_submodel(submodel, options = Hash.new)
                submodel.instance_variable_set(:@field_types, Hash.new)
                submodel.instance_variable_set(:@fields, Array.new)
                submodel.instance_variable_set(:@field_metadata, Hash.new)
                submodel.get_fields.each do |name, offset, type, metadata|
                    if name.respond_to?(:force_encoding)
                        name.force_encoding('ASCII')
                    end
                    submodel.field_types[name] = type
                    submodel.field_types[name.to_sym] = type
                    submodel.fields << [name, type]
                    submodel.field_metadata[name] = metadata
                end

                converted_fields = []
                full_fields = []
                each_field do |name, type|
                    if type.contains_converted_types?
                        converted_fields << name
                    else
                        full_fields << name
                    end
                end
                converted_fields = converted_fields.sort
                full_fields = full_fields.sort

                submodel.instance_variable_set(:@converted_fields, converted_fields)
                overloaded_converted_fields = submodel.
                    filter_methods_that_should_not_be_defined(converted_fields, false)
                overloaded_full_fields = submodel.
                    filter_methods_that_should_not_be_defined(full_fields, true)
                m = access_method_module(overloaded_full_fields, overloaded_converted_fields)
                submodel.include(m)

                super

                if !submodel.convertions_from_ruby.has_key?(Hash)
                    submodel.convert_from_ruby Hash do |value, expected_type|
                        result = expected_type.new
                        result.set_hash(value)
                        result
                    end
                end

                if !submodel.convertions_from_ruby.has_key?(Array)
                    submodel.convert_from_ruby Array do |value, expected_type|
                        result = expected_type.new
                        result.set_array(value)
                        result
                    end
                end
            end

            # Returns true if this compound has no fields
            def empty?
                fields.empty?
            end

            # Returns the offset, in bytes, of the given field
            def offset_of(fieldname)
                fieldname = fieldname.to_str
                get_fields.each do |name, offset, _|
                    return offset if name == fieldname
                end
                raise "no such field #{fieldname} in #{self}"
            end

	    # The list of fields
            attr_reader :fields
            # A name => type map of the types of each fiel
            attr_reader :field_types
            # A name => object mapping of the field metadata objects
            attr_reader :field_metadata
	    # Returns the type of +name+
            def [](name)
                if result = field_types[name]
                    result
                else
                    raise ArgumentError, "#{name} is not a field of #{self.name}"
                end
            end
            # True if the given field is defined
            def has_field?(name)
                field_types.has_key?(name)
            end
	    # Iterates on all fields
            #
            # @yield [name,type] the fields of this compound
            # @return [void]
            def each_field
                return enum_for(__method__) if !block_given?
		fields.each { |field| yield(*field) } 
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
                    each_field.map do |name, type|
                        fields << Hash[name: name, type: type.to_h(options)]
                    end
                else
                    each_field.map do |name, type|
                        fields << Hash[name: name, type: type.to_h_minimal(options)]
                    end
                end

                if options[:layout_info]
                    fields.each do |field|
                        field[:offset] = offset_of(field[:name])
                    end
                end
                super.merge(fields: fields)
            end

	    def pretty_print_common(pp) # :nodoc:
                pp.group(2, '{', '}') do
		    pp.breakable
                    all_fields = get_fields.to_a
                    
                    pp.seplist(all_fields) do |field|
			yield(*field)
                    end
                end
	    end

            def pretty_print(pp, verbose = false) # :nodoc:
		super(pp)
		pp.text ' '
		pretty_print_common(pp) do |name, offset, type, metadata|
                    if doc = metadata.get('doc').first
                        if pp_doc(pp, doc)
                            pp.breakable
                        end
                    end
		    pp.text name
                    if verbose
                        pp.text "[#{offset}] <"
                    else
                        pp.text " <"
                    end
		    pp.nest(2) do
                        type.pretty_print(pp, false)
		    end
		    pp.text '>'
		end
            end

            def initialize_base_class
                super
                @fields = []
                @field_types = Hash.new
                @field_metadata = Hash.new
            end
        end
    end
end

