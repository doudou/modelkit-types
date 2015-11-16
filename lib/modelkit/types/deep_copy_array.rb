module ModelKit::Types
    class DeepCopyArray < Array
        def dup
            result = DeepCopyArray.new
            for v in self
                result << v
            end
            result
        end
    end
end

