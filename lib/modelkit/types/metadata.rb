module ModelKit::Types
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

        def initialize_copy(other)
            @data = Hash.new
            merge(other)
        end

        def merge(metadata)
            metadata.data.each do |k, v|
                (data[k] ||= Set.new).merge(v)
            end
            self
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
            first_line = true
            each do |k, values|
                if values.size == 1
                    pp.text "#{k}: #{values.first}"
                else
                    pp.text "#{k}:"
                    values.each do |v|
                        pp.text "\n- #{v}"
                    end
                end

                if first_line
                    pp.text "\n"
                end
                first_line = false
            end
        end
    end
end

