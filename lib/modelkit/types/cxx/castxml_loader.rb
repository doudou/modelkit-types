require 'modelkit/types/cxx/gccxml_loader'

module ModelKit::Types
    module CXX
        class CastXMLLoader < GCCXMLLoader
            self.binary_path = 'castxml'
            self.default_options = Shellwords.split(ENV['TYPELIB_CASTXML_DEFAULT_OPTIONS'] || '')

            # Runs castxml on the provided file and with the given options, and
            # return the output as a string
            #
            # Raises RuntimeError if casrxml failed to run
            def self.run_importer(file, *cmdline, binary_path: self.binary_path, timeout: self.timeout)
                run_subprocess(binary_path, *cmdline, "--castxml-gccxml", '-x', 'c++', '-o', '-', file, timeout: timeout)
            end

            # Runs castxml on the provided file and with the given options, and
            # return the output as a string
            #
            # Raises RuntimeError if casrxml failed to run
            def self.run_preprocessor(file, *cmdline, binary_path: self.binary_path, timeout: self.timeout)
                run_subprocess(binary_path, '--castxml-gccxml', '-E', *cmdline, file, timeout: timeout)
            end
        end
    end
end

