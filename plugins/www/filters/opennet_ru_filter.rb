# coding: utf-8

class OpennetRuFilter < FilterSkel

	@@rules = {
		'http://www.opennet.ru/opennews/art.shtml?num=42950' => 'piece_of_news',
		'http://www.opennet.ru/openforum/vsluhforumID3/104701.html#1' => 'piece_of_news_with_comments',
	}

	def piece_of_news(arg)
		puts "#{self.class}.#{__method__}(#{arg})"
	end

	def piece_of_news_with_comments(arg)
		puts "#{self.class}.#{__method__}(#{arg})"
	end
end

