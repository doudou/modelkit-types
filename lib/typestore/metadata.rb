module TypeStore
    # Class holding metadata information for types and compound fields
    class MetaData
        attr_reader :data

        def initialize
            @data = Hash.new
        end
        def each
            if !block_given?
                return enum_for(:each)
            end
            data.each do |k, v|
                yield(k, v)
            end
        end

        def empty?
            data.empty?
        end

        def merge(metadata)
            @data = data.merge(metadata.data) do |k, v1, v2|
                v1 | v2
            end
        end
        def add(key, *values)
            (data[key.to_str] ||= Set.new).merge(values)
        end
        def set(key, *values)
            data[key.to_str] = values.to_set
        end
        def get(key)
            data[key] || Set.new
        end
        def clear(key = nil)
            if key
                data.delete(key)
            else
                data.clear
            end
        end
        def [](key)
            get(key)
        end
        def []=(key,value)
            set(key,value)
        end
        def include?(key)
            data.has_key?(key)
        end
        def keys
            data.keys
        end
        def to_hash
            data.dup
        end

        def pretty_print(pp)
            pp.seplist(each.to_a) do |entry|
                key, values = *entry
                pp.text "#{key} ="
                pp.breakable
                pp.seplist(values) do |v|
                    v.pretty_print(pp)
                end
            end
        end
    end
end

