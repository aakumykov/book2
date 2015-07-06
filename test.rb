# coding: utf-8

require 'simple-tidy'

class SimpleTidyMy < SimpleTidy

  #DEFAULT_OPTIONS = { :tidy_mark => false }

  OPTIONS_WITHOUT_VALUES = [ 
		:indent,
		:ashtml,
		:asxhtml,
		:asxml,
		:xml,
		:utf8,
		:numeric,
	]

  SINGLE_DASH_OPTIONS = OPTIONS_WITHOUT_VALUES
end

st = SimpleTidy.new({:utf8 => true})

#data = File.read('Оргазм.html')
puts st.clean('<p>12345</p>')

#~ File.open('out.html','w') { |file|
	#~ file.write( File.read('Оргазм.html') )
#~ }
