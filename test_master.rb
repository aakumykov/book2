# coding: utf-8
system 'clear'
require 'awesome_print'

def LoadRules(dir)

	all_rules = {}

	Dir.entries(dir).each {|file_name|

		if file_name.match(/^\w+_filters\.rb$/) then
			
			Object.send(:remove_const,:RULES) if Object.constants.include?(:RULES)

			file = dir+'/'+file_name
			if (File.exists?(file) and File.readable?(file)) then
				require file
			else
				next
			end

			puts "============ RULES in #{file_name} ============="
			
			RULES.each { |key,value|
				if all_rules.key?(key) then
					puts "Дубликат ключа #{key}! Повторные значения игнорируются."
				else
					all_rules[key] = value
				end
			}
		end
	}

	return all_rules
end

ap LoadRules(Dir.pwd)

