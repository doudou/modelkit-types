module ModelKit::Types
    # Object that manages extensions to types and
    class SpecializationManager
        # A type name to module mapping of the specializations defined by
        # ModelKit::Types.specialize
        attr_reader :value_specializations
        # A type name to module mapping of the specializations defined by
        # ModelKit::Types.specialize_model
        attr_reader :type_specializations
        # A [ruby class, type name] to [options, block] mapping of the custom convertions
        # defined by ModelKit::Types.convert_from_ruby
        attr_reader :convertions_from_ruby
        # A type name to [options, ruby_class, block] mapping of the custom convertions
        # defined by ModelKit::Types.convert_to_ruby. The ruby class might be nil if
        # it has not been specified
        attr_reader :convertions_to_ruby
        
        def initialize
            # Initialize the specialization-related attributes on the ModelKit::Types module
            @value_specializations = RubySpecializationMapping.new(Array.new)
            @type_specializations  = RubySpecializationMapping.new(Array.new)
            @convertions_from_ruby = RubySpecializationMapping.new(Array.new)
            @convertions_to_ruby   = RubySpecializationMapping.new(Array.new)
        end

        # Apply the specializations on the given type (if there are any)
        def apply(type)
            type_specializations, value_specializations =
                self.type_specializations, self.value_specializations
            type.class_eval do
                type_specializations.find_all(type).each do |m|
                    extend m
                end
                value_specializations.find_all(type).each do |m|
                    include m
                end
            end

            convertions_from_ruby.find_all(type).each do |conv|
                type.convert_from_ruby(conv.ruby, &conv.block)
            end
            if conv = convertions_to_ruby.find(type, error_if_ambiguous: false)
                type.convert_to_ruby(conv.ruby, &conv.block)
            end
        end

        # Adds methods to the type objects.
        #
        # The objects returned by registry.get(type_name) are themselves classes.
        # This method allows to define singleton methods, i.e. methods that will be
        # available on the type objects returned by Registry#get
        #
        # See ModelKit::Types.specialize to add instance methods to the values of a given
        # ModelKit::Types type
        def specialize_model(name, options = Hash.new, &block)
            options[:if] = options[:if] || proc { true }
            type_specializations.add(name, Module.new(&block), options)
        end

        # Extends instances of a given ModelKit::Types type
        #
        # This method allows to add methods that are then available on ModelKit::Types
        # values.
        #
        # For instance, if we assume that a Vector3 type is defined by
        #
        #   struct Vector3
        #   {
        #     double data[3];
        #   };
        #
        # Then
        #
        #   ModelKit::Types.specialize '/Vector3' do
        #     def +(other_v)
        #       result = new
        #       3.times do |i|
        #         result.data[i] = data[i] + other_v.data[i]
        #       end
        #     end
        #   end
        #
        # will make it possible to add two values of the Vector3 type in Ruby
        def specialize(name, options = Hash.new, &block)
            options[:if] = options[:if] || proc { true }
            value_specializations.add(name, TypeSpecializationModule.new(&block), options)
        end

        # Representation of a declared ruby-to-modelkit/types or modelkit/types-to-ruby convertion
        class Convertion
            # The type that we are converting from
            #
            # It is an object that can match type names
            #
            # @return [String,Regexp]
            attr_reader :matcher
            # The type that we are converting to, if known. It cannot be nil if this
            # object represents a ruby-to-matcher
            #
            # @return [Class,nil]
            attr_reader :ruby
            # The convertion proc
            attr_reader :block

            def initialize(matcher, ruby, block)
                @matcher, @ruby, @block = matcher, ruby, block
            end
        end

        # Declares how to convert values of the given type to an equivalent Ruby
        # object
        #
        # For instance, given a hypothetical timeval type that would be defined (in C) by
        #
        #   struct timeval
        #   {
        #       int32_t seconds;
        #       uint32_t microseconds;
        #   };
        #
        # one could make sure that timeval values get automatically converted to
        # Ruby's Time with
        #
        #   ModelKit::Types.convert_to_ruby '/timeval' do |value|
        #     Time.at(value.seconds, value.microseconds)
        #   end
        #
        #
        # Optionally, for documentation purposes, it is possible to specify in what
        # type will the ModelKit::Types be converted:
        #
        #   ModelKit::Types.convert_to_ruby '/timeval', Time do |value|
        #     Time.at(value.seconds, value.microseconds)
        #   end
        def convert_to_ruby(typename, ruby_class = nil, options = Hash.new, &block)
            if ruby_class.kind_of?(Hash)
                ruby_class, options = nil, options
            end

            if ruby_class && !ruby_class.kind_of?(Class)
                raise ArgumentError, "expected a class as second argument, got #{to}"
            end
            convertions_to_ruby.add(typename, Convertion.new(typename, ruby_class, lambda(&block)), options)
        end

        # Define specialized convertions from Ruby objects to ModelKit::Types-managed
        # values.
        #
        # For instance, to allow the usage of Time instances to initialize structure
        # fields of the timeval type presented in ModelKit::Types.specialize_model, one
        # would do
        #
        #   ModelKit::Types.convert_from_ruby Time, '/timeval' do |value, typestore_type|
        #     v = typestore_type.new
        #     v.seconds      = value.tv_sec
        #     v.microseconds = value.tv_usec
        #   end
        #
        # It will then be possible to do
        #
        #   a.time = Time.now
        #
        # where 'a' is a value of a structure that has a 'time' field of the timeval
        # type, as for instance
        #
        #   struct A
        #   {
        #     timeval time;
        #   };
        #
        def convert_from_ruby(ruby_class, typename, options = Hash.new, &block)
            options[:if] = options[:if] || proc { true }
            if !ruby_class.kind_of?(Class)
                raise ArgumentError, "expected a class as first argument, got #{ruby_class}"
            end
            convertions_from_ruby.add(typename, Convertion.new(typename, ruby_class, lambda(&block)), options)
        end 
    end
end

