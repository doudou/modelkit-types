require 'modelkit/types/cxx/std_vector'
require 'modelkit/types/cxx/basic_string'
require 'modelkit/types/cxx/registry'

# C++ support
#
# More than one loader are supported (e.g. clang or gccxml). The specific
# loaders are defined under this module, while the generic facade is
# IO::CXXImporter
module ModelKit::Types
    module CXX
        def self.parse_template(name)
            tokens = template_tokenizer(name)

            type_name = tokens.shift
            arguments = collect_template_arguments(tokens)
            arguments.map! do |arg|
                arg.join("")
            end
            return type_name, arguments
        end

        def self.collect_template_arguments(tokens)
            level = 0
            arguments = []
            current = []
            while !tokens.empty?
                case tk = tokens.shift
                when "<"
                    level += 1
                    if level > 1
                        current << "<" << tokens.shift
                    else
                        current = []
                    end
                when ">"
                    level -= 1
                    if level == 0
                        arguments << current
                        current = []
                        break
                    else
                        current << ">"
                    end
                when ","
                    if level == 1
                        arguments << current
                        current = []
                    else
                        current << "," << tokens.shift
                    end
                else
                    current << tk
                end
            end
            if !current.empty?
                arguments << current
            end

            return arguments
        end

        def self.template_tokenizer(name)
            suffix = name
            result = []
            while !suffix.empty?
                suffix =~ /^([^<,>]*)/
                match = $1.strip
                if !match.empty?
                    result << match
                end
                char   = $'[0, 1]
                suffix = $'[1..-1]

                break if !suffix

                result << char
            end
            result
        end
    end
end

