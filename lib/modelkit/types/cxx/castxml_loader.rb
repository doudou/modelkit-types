require 'modelkit/types/cxx/gccxml_loader'

module ModelKit::Types
    module CXX
        class CastXMLLoader < GCCXMLLoader
            def self.import(file, registry: Registry.new, **options)
                super(file, registry: registry, castxml: true, **options)
            end
            def self.preprocess(files, **options)
                super(files, castxml: true, **options)
            end
        end
    end
end

