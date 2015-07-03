module TypeStore
    module Models
        module CompoundType
            include Type

            class Field
                attr_reader :compound
                attr_reader :name
                attr_reader :type
                attr_accessor :offset

                def metadata; @metadata ||= MetaData.new end

                def has_metadata?; @metadata && !@metadata.empty? end

                def initialize(compound, name, type, offset: nil)
                    @compound, @name, @type, @offset = compound, name, type, offset
                end

                def validate_merge(field)
                    if field.name != name
                        raise ArgumentError, "invalid field passed to #merge: name mismatches"
                    end

                    if field.offset != offset
                        raise MismatchingFieldOffsetError, "field #{name} is at offset #{offset} in #{compound} and at #{field.offset} in #{field.compound}"
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

            def initialize_base_class
                super
                self.name = "TypeStore::CompoundType"
            end

            def ==(other)
                super && fields == other.fields
            end

            def casts_to?(type)
                super || (f = fields.first && f.type == type)
            end

	    # Called by the extension to initialize the subclass
	    # For each field, it creates getters and setters on 
	    # the object, and a getter in the singleton class 
	    # which returns the field type
            def setup_submodel(submodel, registry: self.registry, typename: nil, size: 0, opaque: false, null: false, &block)
                super

                submodel.instance_variable_set(:@fields, Hash.new)
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

            def copy_to(registry, **options)
                model = super
                fields.each do |field_name, field|
                    field_type =
                        if registry.find_by_name(field.type.name) 
                            registry.get(field.type.name)
                        else field.type.copy_to(registry)
                        end

                    new_field = model.add(field_name, field_type, offset: field.offset)
                    new_field.metadata.merge(field.metadata)
                end
                model
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
                                     silent: !warn_about_helper_method_clashes?)

                candidates = [name, "#{name}="]
                if with_raw
                    candidates.concat(["raw_#{name}", "raw_#{name}="])
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
            def add(name, type, offset: nil)
                name = name.to_str
                if fields[name]
                    raise DuplicateFieldError, "#{self} already has a field called #{name}"
                elsif type.respond_to?(:to_str)
                    type = registry.build(type)
                elsif type.registry != registry
                    raise NotFromThisRegistryError, "#{type} is from #{type.registry} and #{self} is from #{registry}, cannot add a field"
                end

                add_direct_dependency(type)

                field = Field.new(self, name, type, offset: offset)
                fields[name] = field
                self.contains_opaques = self.contains_opaques? || type.contains_opaques? || type.opaque?
                self.contains_converted_types = self.contains_converted_types? || type.contains_converted_types? || type.needs_convertion_to_ruby?
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

            # Returns true if this compound has no fields
            def empty?
                fields.empty?
            end

            # Returns the offset, in bytes, of the given field
            #
            # @param (see #get)
            # @raise (see #get)
            # @return [Integer]
            def offset_of(fieldname)
                get(fieldname).offset
            end

            # Alias for {get}
            def [](name); get(name) end

            # Accesses a field by name
            #
            # @param [#to_str] name the field name
            # @return [Field]
            # @raise [FieldNotFound] if there are no fields with this name
            def get(name)
                name = name.to_str
                if result = fields[name]
                    result
                else
                    raise FieldNotFound, "#{name} is not a field of #{self} (fields are #{fields.keys.join(", ")})"
                end
            end

            # True if the given field is defined
            def has_field?(name)
                fields.has_key?(name.to_str)
            end

            # Enumerates the compound's fields
            #
            # @yieldparam [Field] field
            def each(&block)
                fields.each_value(&block)
            end

	    # @deprecated use {#each} instead
            #
            # Iterates on all fields
            #
            # @yield [name,type] the fields of this compound
            # @return [void]
            def each_field
                return enum_for(__method__) if !block_given?
                fields.each_value { |field| yield(field.name, field.type) } 
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
                type_fields = type.fields.dup
                each do |f|
                    if type_f = type_fields.delete(f.name)
                        f.validate_merge(type_f)
                    else
                        raise MismatchingFieldSetError, "field #{f.name} is present in #{self} but not in #{type}"
                    end
                end
                if !type_fields.empty?
                    raise MismatchingFieldSetError, "fields #{type_fields.keys.sort.join(", ")} are present in #{type} but not in #{self}"
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

            def pretty_print(pp, verbose = false) # :nodoc:
		super(pp)
		pp.text ' '
		pretty_print_common(pp) do |field|
                    if doc = field.metadata.get('doc').first
                        if pp_doc(pp, doc)
                            pp.breakable
                        end
                    end
                    pp.text field.name
                    if verbose
                        pp.text "[#{field.offset}] <"
                    else
                        pp.text " <"
                    end
		    pp.nest(2) do
                        field.type.pretty_print(pp, false)
		    end
		    pp.text '>'
		end
            end

            # Apply a set of type-to-size mappings
            #
            # @return [Integer,nil] the type's new size if it needs to be resized
            def apply_resize(typemap)
                fields = self.fields.values.sort_by { |f| f.offset }
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

