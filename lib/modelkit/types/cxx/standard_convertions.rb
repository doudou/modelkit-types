module ModelKit::Types
    # Get the name for 'char'
    reg = Registry.new(false)
    Registry.add_standard_cxx_types(reg)
    CHAR_T = reg.get('/char')
    INT_BOOL_T = reg.get("/int#{reg.get('/bool').size * 8}_t")

    convert_from_ruby TrueClass, '/bool' do |value, typestore_type|
        ModelKit::Types.from_ruby(1, typestore_type)
    end
    convert_from_ruby FalseClass, '/bool' do |value, typestore_type|
        ModelKit::Types.from_ruby(0, typestore_type)
    end
    convert_to_ruby '/bool' do |value|
        ModelKit::Types.to_ruby(value, INT_BOOL_T) != 0
    end

    %w{uint8_t uint16_t uint32_t uint64_t
       int8_t int16_t int32_t int64_t
       float double}.each do |numeric_type|
        specialize "/std/vector</#{numeric_type}>" do
            def __element_to_ruby(element)
                element.to_ruby
            end
        end
    end

    convert_from_ruby String, '/std/string' do |value, typestore_type|
        typestore_type.wrap([value.length, value].pack("QA#{value.length}"))
    end
    convert_to_ruby '/std/string', String do |value|
        value = value.to_byte_array[8..-1]
        if value.respond_to?(:force_encoding)
            value.force_encoding(Encoding.default_internal || __ENCODING__)
        end
        value
    end
    specialize '/std/string' do
        def to_str
            ModelKit::Types.to_ruby(self)
        end

        def pretty_print(pp)
            pp.text to_str
        end

        def to_simple_value(options = Hash.new)
            to_ruby
        end

        def concat(other_string)
            if other_string.respond_to?(:to_str)
                super(ModelKit::Types.from_ruby(other_string, self.class))
            else super
            end
        end
    end
    specialize '/std/vector<>' do
        include ModelKit::Types::ContainerType::StdVector
    end

    ####
    # C string handling
    if String.instance_methods.include? :ord
        convert_from_ruby String, CHAR_T.name do |value, typestore_type|
            if value.size != 1
                raise ArgumentError, "trying to convert '#{value}', a string of length different than one, to a character"
            end
            ModelKit::Types.from_ruby(value[0].ord, typestore_type)
        end
    else
        convert_from_ruby String, CHAR_T.name do |value, typestore_type|
            if value.size != 1
                raise ArgumentError, "trying to convert '#{value}', a string of length different than one, to a character"
            end
            ModelKit::Types.from_ruby(value[0], typestore_type)
        end
    end
    convert_from_ruby String, "#{CHAR_T.name}[]" do |value, typestore_type|
        result = typestore_type.new
        Type::from_string(result, value, true)
        result
    end
    convert_to_ruby "#{CHAR_T.name}[]", String do |value|
        value = Type::to_string(value, true)
        if value.respond_to?(:force_encoding)
            value.force_encoding('ASCII')
        end
        value
    end
    specialize "#{CHAR_T.name}[]" do
        def to_str
            value = Type::to_string(self, true)
            if value.respond_to?(:force_encoding)
                value.force_encoding('ASCII')
            end
            value
        end
    end
    convert_from_ruby String, "#{CHAR_T.name}*" do |value, typestore_type|
        result = typestore_type.new
        Type::from_string(result, value, true)
        result
    end
    convert_to_ruby "#{CHAR_T.name}*", String do |value|
        value = Type::to_string(value, true)
        if value.respond_to?(:force_encoding)
            value.force_encoding('ASCII')
        end
        value
    end
    specialize "#{CHAR_T.name}*" do
        def to_str
            value = Type::to_string(self, true)
            if value.respond_to?(:force_encoding)
                value.force_encoding('ASCII')
            end
            value
        end
    end
end


