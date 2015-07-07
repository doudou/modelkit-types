require 'typestore/cxx'
require 'typestore/cxx/gccxml_loader'
require 'typestore/cxx/clang_loader'

module TypeStore
    module IO
        module CXXImporter
            CXX_LOADERS = Hash[
                'gccxml' => CXX::GCCXMLLoader,
                'clang'  => CXX::CLangLoader
            ]

            class << self
                # Explicitly sets {loader}
                attr_writer :loader
            end

            # Returns the current C++ loader object
            #
            # The value of {loader} is initialized either by setting it explicitely
            # with {loader=} or by setting the TYPESTORE_CXX_LOADER to the name of a
            # loader registered in {CXX_LOADERS}.
            #
            # The default is currently GCCXMLLoader
            #
            # @return [#load,#preprocess] a loader object suitable for operating
            #   on C++ files
            def self.loader
                if @loader
                    @loader
                elsif cxx_loader_name = ENV['TYPESTORE_CXX_LOADER']
                    cxx_loader = CXX_LOADERS[cxx_loader_name]
                    if !cxx_loader
                        raise ArgumentError, "#{cxx_loader_name} is not a known C++ loader, known loaders are '#{CXX_LOADERS.keys.sort.join("', '")}'"
                    end
                    cxx_loader
                else
                    CXX::GCCXMLLoader
                end
            end

            # Loads a C++ file and imports it in the given registry, based on the
            # current C++ importer setting
            def self.import(path, registry: CXX::Registry.new, **options)
                loader.import(path, registry: registry, **options)
            end

            def self.preprocess(files, options)
                loader.preprocess(files, options)
            end
        end
    end
    Registry::IMPORT_TYPE_HANDLERS['c'] = IO::CXXImporter
end
