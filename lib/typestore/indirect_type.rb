module TypeStore
    class IndirectType < Type
        extend Models::IndirectType

        def ==(other)
            super &&
                deference == other.deference
        end
    end
end

