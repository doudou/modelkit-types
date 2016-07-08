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
            def self.run_importer(file, *cmdline, binary_path: self.binary_path)
                result = ::IO.popen([binary_path, *cmdline, "--castxml-gccxml", '-x', 'c++', '-o', '-', file]) do |io|
                    io.read
                end
                if !$?.success?
                    raise ImportProcessFailed, "#{binary_path} failed, see error messages above for more details"
                end
                result
            end

            # Runs castxml on the provided file and with the given options, and
            # return the output as a string
            #
            # Raises RuntimeError if casrxml failed to run
            def self.run_preprocessor(file, *cmdline, binary_path: self.binary_path)
                result = ::IO.popen(binary_path, '--castxml-gccxml', '-E', *cmdline) do |io|
                    io.read
                end
                if !$!.success?
                    raise ArgumentError, "#{binary_path} failed, see error messages above for more details"
                end
                result
            end
        end
    end
end

