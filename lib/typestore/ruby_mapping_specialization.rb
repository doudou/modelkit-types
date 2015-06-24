module TypeStore
    # Class used to register type-to-object mappings.
    #
    # Customizations can eithe be registered as string-to-object or
    # regexp-to-object mappings. We have to go through all regexps in the second
    # case, so we split the two matching methods to speed up the common case
    # (strings)
    class RubyMappingCustomization
        # Mapping from type names to registered objects
        # @return [{String=>Object}]
        attr_reader :from_typename
        # Mapping from the element type name of an array
        # @return [{String=>Object}]
        attr_reader :from_array_basename
        # Mapping from the container type name
        # @return [{String=>Object}]
        attr_reader :from_container_basename
        # Mapping from regexps matching type names to registered objects
        # @return [{Regexp=>Object}]
        attr_reader :from_regexp
        # A stereotypical container that should be used as base object in
        # {from_regexp} and {from_type}. If nil, only one object can be
        # registered at the time
        attr_reader :container

        def initialize(container = nil)
            @from_typename = Hash.new
            @from_array_basename = Hash.new
            @from_container_basename = Hash.new
            @from_regexp = Hash.new
            @container = container
        end

        # Returns the right mapping object for that key
        #
        # @return [String,Hash] one of the from_* sets as well as the string
        #   that should be used as key
        def mapping_for_key(key)
            if key.respond_to?(:to_str)
                suffix = key[-2, 2]
                if suffix == "<>"
                    return key[0..-3], from_container_basename
                elsif suffix == "[]"
                    return key[0..-3], from_array_basename
                else 
                    return key, from_typename
                end
            else return key, from_regexp
            end
        end

        # Sets the value for a given key
        #
        # @param [Regexp,String] the object that will be used to match the type
        #   name
        # @param [Object] value the value to be stored for that key
        def set(key, value, **options)
            options[:if] = options[:if] || Hash.new(true)
            key, set = mapping_for_key(key)
            set = set[key] = (container || Array.new).dup
            set << [options, value]
        end

        # Add a value to a certain key. Note that this is only possible if a
        # container has been given at construction time
        #
        # @raise [ArgumentError] if this registration class does not support
        #   having more than one value per key
        #
        # @param [Regexp,String] the object that will be used to match the type
        #   name
        # @param [Object] value the value to be added to the set for that key
        def add(key, value, **options)
            options[:if] = options[:if] || Hash.new(true)
            if !container
                raise ArgumentError, "#{self} does not support containers"
            end
            key, set = mapping_for_key(key)
            set = (set[key] ||= container.dup)
            set << [options, value]
        end

        # Returns the single object registered for the given type name
        #
        # @raise [ArgumentError] if more than one matching object is found
        def find(type_model, error_if_ambiguous = true)
            all = find_all(type_model)
            if all.size > 1 && error_if_ambiguous
                raise ArgumentError, "more than one entry matches #{name}"
            else all.first
            end
        end

        # Returns all objects matching the given type name
        #
        # @raise [Array<Object>]
        def find_all(type_model, name = type_model.name)
            # We delegate the building of candidates to the type models to avoid
            # weird dependency issues (i.e. RubyMappingCustomization must be
            # available when the submodels are created, which means that we
            # can't access the type classes from there)
            candidates = type_model.ruby_convertion_candidates_on(self)
            candidates.map do |options, obj|
                obj if options[:if].call(type_model)
            end.compact
        end
    end
end

