# coding: utf-8
system 'clear'
require 'awesome_print'

log=[]
freq = {}

38.times { log << rand(5) }
p "log: #{log.join.gsub(',','').gsub('2','/2/')}"

string = log.map!{|el| "@#{el}@" }.join(',')
string = string.gsub!(/^.*?@2@/,'@2@')
string = string.split(',').reverse.join(',')
string = string.gsub!(/^.*?@2@/,'@2@')
string = string.split(',').reverse.join(',')

parts = string.split('@2@').map!{|el| el.gsub(/^,|,$/,'').gsub('@','') }
parts.shift
puts "parts: #{parts.map! {|el| "|#{el.gsub(',','')}|"}.join(' , ')}"

parts.each { |chain|
	if freq.key?(chain) then
		freq[chain] += 1
	else
		freq[chain] = 1
	end
}

ap freq 
