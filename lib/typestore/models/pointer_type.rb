module TypeStore
    module Models
        module PointerType
            include IndirectType

            # Creates and initializes to zero a value of this pointer type
            def create_null
                result = new
                result.zero!
                result
            end

            def to_ruby(value)
                if value.null? then nil
                else value
                end
            end
        end
    end
end

