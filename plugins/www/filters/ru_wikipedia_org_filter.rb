# coding: utf-8

class RuWikipediaOrgFilter < FilterSkel

	@@rules = {
		'^https:\/\/ru\.wikipedia\.org\/wiki\/[\w%]+' => 'article',
		'^https:\/\/ru\.wikipedia\.org\/w\/index\.php\?title=[\w%]+&printable=yes' => 'article_printable',
	}

	def self.rules
		@@rules
	end

	def article(arg)
		puts "#{self.class}.#{__method__}(#{arg})"
	end

	def article_printable(arg)
		puts "#{self.class}.#{__method__}(#{arg})"
	end
end
