require 'modelkit/types/cxx'
require 'modelkit/types/cxx/gccxml_loader'
require 'modelkit/types/cxx/castxml_loader'
require 'tty/which'

module ModelKit::Types
    module IO
        module CXXImporter
            CXX_LOADERS = Hash[
                'gccxml'   => CXX::GCCXMLLoader,
                'castxml'  => CXX::CastXMLLoader
            ]

            class << self
                # Explicitly sets {loader}
                attr_writer :loader
            end

            class ImporterNotFound < RuntimeError; end

            def self.select_loader_by_name(cxx_loader_spec)
                cxx_loader = CXX_LOADERS[cxx_loader_spec]
                if cxx_loader
                    cxx_loader_name = cxx_loader_spec
                    if !(cxx_loader_path = TTY::Which.which(cxx_loader_name))
                        raise ImporterNotFound, "cannot find '#{cxx_loader_name}' in PATH"
                    end
                elsif match = CXX_LOADERS.find { |name, loader| cxx_loader_spec.start_with?("#{name}:") }
                    cxx_loader_name, cxx_loader = match
                    cxx_loader_path = cxx_loader_spec[(cxx_loader_name.size + 1)..-1]
                    if !TTY::Which.exist?(cxx_loader_path)
                        raise ImporterNotFound, "#{cxx_loader_path}, specified in the MODELKIT_TYPES_CXX_LOADER environment variable, does not exist"
                    end
                elsif matches = CXX_LOADERS.find_all { |name, loader| cxx_loader_spec =~ /#{name}/ }
                    if matches.size == 1
                        cxx_loader_name, cxx_loader = matches.first
                        if !TTY::Which.exist?(cxx_loader_spec)
                            raise ImporterNotFound, "C++ importer binary path #{cxx_loader_spec}, specified in MODELKIT_TYPES_CXX_LOADER, does not exist"
                        end
                        cxx_loader_path = cxx_loader_spec
                    elsif matches.empty?
                        raise ImporterNotFound, "cannot find an importer matching #{cxx_loader_spec}, set in MODELKIT_TYPES_CXX_LOADER. Use the 'loader_method:/path/to/binary' syntax (where loader_method is one of #{CXX_LOADERS.keys.sort.join(", ")}), or simply 'loader_method' if the corresponding loader binary (e.g. 'castxml') can be found in PATH"
                    else
                        raise ImporterNotFound, "more than one importer match #{cxx_loader_spec}, specify the import type (#{CXX_LOADERS.keys.sort.join(", ")}) explicitely with the importer_type:/path/to/importer syntax"
                    end
                end

                @loader = cxx_loader
                loader.binary_path = cxx_loader_path
                @loader
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
                    return @loader
                end

                cxx_loader_spec = ENV['MODELKIT_TYPES_CXX_LOADER']
                if !cxx_loader_spec
                    if castxml_path = TTY::Which.which('castxml')
                        cxx_loader_spec = "castxml:#{castxml_path}"
                    elsif gccxml_path = TTY::Which.which('gccxml')
                        cxx_loader_spec = "gccxml:#{gccxml_path}"
                    else
                        raise ImporterNotFound, "cannot find a suitable C++ importer (tried to find castxml and gccxml). Set MODELKIT_TYPES_CXX_LOADER to the full path to a suitable binary. Alternatively, use the loader_name:/path/to/binary if the binary name does not match the expected 'castxml' or 'gccxml' (e.g. export MODELKIT_TYPES_CXX_IMPORTER=gccxml:/usr/bin/a_compatible_importer)"
                    end
                end

                select_loader_by_name(cxx_loader_spec)
            end

            @loader = nil

            # Loads a C++ file and imports it in the given registry, based on the
            # current C++ importer setting
            def self.import(path, registry: CXX::Registry.new, cxx_importer: loader, **options)
                cxx_importer.import(path, registry: registry, **options)
                registry
            end

            def self.preprocess(files, cxx_importer: loader, **options)
                cxx_importer.preprocess(files, options)
            end
        end
    end
    Registry::IMPORT_TYPE_HANDLERS['c'] = IO::CXXImporter
end

