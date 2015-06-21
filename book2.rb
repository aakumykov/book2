#!/usr/bin/env ruby
# coding: utf-8

# СДЕЛАТЬ:
# * упорядочить public / private
# * escapeshell{arg,cmd}
#
# Вопросы для решения:
# * индивидуальная обработка глубины каждого источника
# * дубликаты ссылок в БД
# * производительность БД
# * нормализация URI (для использования в качестве хэша)
# * жизнь кодировок
# * вывод ошибок в stderr
# * при ошибке сохранения ссылки всё равно устанавливается статус 'processed'
#
# ОШИБКИ:
# * знак # кодируется в %23, который потом не срабатывает при открытии ссылки
#
# ОСОБЕННОСТИ:
# * ранжирование фильтров по частоте срабатывания
#
# ЖУРНАЛ ИЗМЕНЕНИЙ:
# * 2015.06.21 переписал collectLinks(); перевёл с SimpleURI обратно на URI; исключил из обработки ссылки с 'action=edit'
#
#

system 'clear'

require 'rubygems'
require 'open-uri'
require 'sqlite3'
require 'securerandom'
require 'digest/md5'
require 'tmpdir'
require 'nokogiri'
require 'curl'	# must be before 'colorize'
require 'colorize'	# must be after 'curl' for right colors
require 'awesome_print'
require 'uri'


class Msg

	def Msg.debug(arg)
		#puts arg.to_s.white + 10.chr
	end

	def Msg.info(arg)
		puts arg.to_s + 10.chr
	end

	def Msg.error(arg)
		puts ("ОШИБКА: " + arg.to_s).red + 10.chr
	end
	
	def Msg.alert(arg)
		puts ("###: " + arg.to_s).yellow + 10.chr
	end
	
	def Msg.info_blue(arg)
		puts arg.to_s.blue + 10.chr
	end
	
	def Msg.info_green(arg)
		puts arg.to_s.green + 10.chr
	end
end

class String
	def urlencoded?
		return true if self.match(/[%0-9ABCDEF]{3,}/i)
		return false
	end
end

class Book

	attr_accessor :title, :author
	
	# методы первого уровня
	public

	# настроить
	def initialize(title,options={})
		Msg.info "#{__method__}('#{title}','#{author}')"
		
		@user_agent = 'Ruby/1.9.3, Contacts: aakumykov@yandex.ru'

		# свойства книги
		self.title = title.to_s.strip
		self.author = author.to_s.strip.empty? ? 'неизвестный автор' : author

		# каталоги
		@@script_name = File.basename(File.realpath(__FILE__)).split('.')[0]
		@work_dir = Dir.tmpdir + '/' + @@script_name
		Dir.mkdir(@work_dir) if not Dir.exists?(@work_dir)
		Msg.debug("work_dir: #{@work_dir}")

		@book_dir = @work_dir + '/' + self.title.gsub(/\s/,'_')
		Dir.mkdir(@book_dir) if not Dir.exists?(@book_dir)
		
		# удаляю старые файлы
		Dir.new(@book_dir).each { |item| File.delete "#{@book_dir}/#{item}" if item.match(/\.html/) }
		
		# журнал ошибок
		@@error_log = "#{@@script_name}-errors.log"
		File.open(@@error_log,'w') { |file| true }
		
		# рабочие параметры
		@threads = 1
		@threads = options[:threads].to_i if not options[:threads].nil?

		@options = {}
		@filters = {}
		
		@current_depth = 0
		@target_depth = 0
		@target_depth = options[:depth].to_i if not options[:depth].nil?
		
		@page_count = 0 
		@page_limit = 5		# 0 (zero) disables this limit
		@page_limit = options[:pages].to_i if not options[:pages].nil?
		
		@errors_count = 0
		@errors_limit = 5
		
		@timeout_limit = 60
		
		case options[:db_type] 
		when 'file'
			@db_name = 'db_' + @@script_name + '.sqlite'
		else
			@db_name = ':memory:'
		end
		
		@table_name = 'book_info'

		table_def = [
			"CREATE TABLE #{@table_name} (",
			'id TEXT PRIMARY KEY',
			',',
			'parent_id TEXT',
			',',
			'depth INT',
			',',
			'status TEXT',
			',',
			'uri TEXT',
			',',
			'archor_name TEXT',
			',',
			'title TEXT',
			',',
			'file TEXT',
			')'
		]

		@db = SQLite3::Database.new(@db_name)
		
		@db.results_as_hash = true
		@db.execute("PRAGMA journal_mode=OFF")
		
		@db.execute("DROP TABLE IF EXISTS #{@table_name}")
		
		q = table_def.join(' ')
		@db.execute(q)
		
		#system "ls -l #{@db_name}"
	end

	def addSource(uri)
		Msg.info "#{__method__}(#{uri})"
				
		link = URI::encode(uri) if not uri.urlencoded?
		link = URI(link)
		
		id = SecureRandom.uuid
		
		saveLink(id, 0, 0, link.to_s)

		@filters[link.host] = {
			'links' => [],
			'pages' => {}
		}

		return id
	end
	
	def addFilter(filter)
		Msg.info "#{__method__}(#{filter.keys})"
		
		@filters.merge!(filter)
		
		#pp @filters
	end

	def prepare()
		
		Msg.info "#{__method__}()"
		
		# пока не будет готово
		while ( not prepareComplete? and freshLinksExists?(@current_depth) ) do
				
			Msg.debug "CURRENT: pages #{@page_count}, depth #{@current_depth}"
			
			# брать порцию ссылок
			links = getFreshLinks(@current_depth, @threads)
			
			# и обрабатывать (в потоках)
			threads = []
			
			links.each { |row|

				source_id = row['id']
				source_uri = row['uri']
				
				# зарядить нить обработки
				threads << Thread.new(source_uri) { |uri|
				
					Msg.info ""

					# получишь страницу
					source_page = loadPage(uri)
					
					# выделишь заголовок
					page_title = extractTitle(source_page)
					Msg.info_green "заголовок: #{page_title}"
					
					# обрежешь и сохранишь страницу
					page_body = extractBody(source_page,source_uri)
					
					# сохранишь страницу
					savePage({
						:id => source_id,
						:title => page_title,
						:body => page_body,
					})
					
					# выделишь и сохранишь ссылки
					new_links = extractLinks(source_page,uri)

					new_links.each { |link|
						saveLink( 
							SecureRandom.uuid, 
							source_id, 
							@current_depth+1, 
							link 
						)
					}
					
					setLinkStatus(source_id,{:status=>'processed'})
					
					@page_count += 1
				}
			}
			
			# запустить обработку в нитях
			threads.each { |thr| thr.join }
		
			# увеличить глубину по выработке текущей
			@current_depth += 1 if not freshLinksExists?(@current_depth)
			
			if 1 != @threads then
				print "Ждём 5 секунд"; 4.times { sleep 1 and print '.' }; sleep 1 and puts '.'
			end
		end		
		
	end
	
	def create(file='')
		Msg.info "#{__method__}(#{file})"
	end


	private
	
	def prepareComplete?
	
		#return @current_depth == @target_depth
		
		if @current_depth > @target_depth then
			reason = "достигнута глубина #{@target_depth}"
		
		elsif @errors_count > @errors_limit then
			reason = "достигнут максимум ошибок (#{@errors_limit})"
		
		elsif ( (0 != @page_limit) and (@page_count >= @page_limit) ) then
			reason = "достигнут максимум страниц (#{@page_limit})"
		
		else
			return false
		end

		Msg.info ""
		Msg.info_blue "===== #{reason} ====="
		return true
	end

	def freshLinksExists?(depth)
		#Msg.debug "#{__method__}(#{depth})"
		
		q = "SELECT * FROM #{@table_name} WHERE depth='#{depth}' AND status='fresh'"
		res = @db.execute(q)
		res = res.count != 0
		
		#Msg.debug  "#{__method__}(depth #{depth}) ==> #{res}"
		
		return res
	end

	def getFreshLinks ( depth, amount )
		Msg.debug "#{__method__}(#{depth},#{amount})"
		q = "SELECT * FROM #{@table_name} WHERE status='fresh' AND depth=#{depth} LIMIT #{amount}"
		res = @db.execute(q)
		
		res.each { |row| Msg.debug "#{row['uri']}" }
		
		return res
	end
	
	def loadPage(uri)
		Msg.info_blue "#{__method__}('#{uri.urlencoded? ? URI::decode(uri) : uri}')"
		
		curl = CURL.new
		curl.user_agent = @user_agent
		page = curl.get(uri)

		return page
	end
	
	def extractLinks(html_data,uri,filter='')
		Msg.debug "#{__method__} from page '#{uri}'"
		
		links = collectLinks(uri,html_data)
		#puts "collected: #{links.size}"
		
		filter = getFilterFor(uri,'links')
		
		links = filterLinks(links,filter)
		#puts "filtered: #{links.size}"

		return links
	end
	
	def saveLink(id, parent_id, depth, uri)
		#Msg.info "#{__method__}(#{id}, #{parent_id}, #{depth}, #{uri})"
		#Msg.info "#{__method__}(#{uri})"
		
		uri = URI::encode(uri) if not uri.urlencoded?
		
		q = [
			"INSERT INTO #{@table_name}",
			'(id, parent_id, depth, status, uri) VALUES ',
			"(",
				"?", ',',
				"?", ',',
				"?", ',',
				"?", ',',
				"?",
			")",
		]
		
		q = q.join(' ')
		#puts "|#{q}|";
		
		begin
			@db.prepare(q).execute(
				id,
				parent_id,
				depth,
				'fresh',
				uri
			)
		rescue
			Msg.error "|#{q}|"
			File.open(@@error_log,'a') { |file|
				file.write(q)
			}
		end
	end
	
	def savePage(arg)
		id = arg[:id]
		title = arg[:title]
		page_body = arg[:body]
		
		file_name = @book_dir+"/"+arg[:id]+".html"
		
		Msg.info "#{__method__}('#{title}', '#{file_name}'), body size: #{page_body.size}"

		File.open(file_name,'w') { |file|
			file.write <<QWERTY
 <!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 4.01 Transitional//EN"
     "http://www.w3.org/TR/html4/loose.dtd">
<html>
<head>
<meta http-equiv='Content-Type' Content='text/html;charset=UTF-8'>
<title>#{title}</title>
</head>
<body>
#{page_body}
</body>
</html>
QWERTY
		}
	end
	
	def setLinkStatus(id,options)
		Msg.info "#{__method__}(), #{id}, #{options}"
		q = "UPDATE #{@table_name} SET status='#{options[:status]}' WHERE id='#{id}'"
		@db.execute(q)
	end
	
	
	# методы второго уровня
	def getOptions(id)
		Msg.debug "#{__method__}(#{id})"
		
		if @options.has_key?(id) then
			return @options[id]
		else
			return {}
		end
	end

	def getFilterFor(uri,mode)
		Msg.debug "#{__method__}(#{uri},'#{mode}')"
		
		host = URI(uri).host
		
		case mode
			when 'links'
				Msg.debug "items in filter: #{@filters[host]['links'].size}"
				
				return @filters[host]['links']

			when 'page'
				@filters[host]['pages'].each { |pattern,rule|
					return rule if uri.match(pattern) 
				}
				return '/'

			else
				Msg.error "неизвестный режим '#{mode}'"
				return nil
		end
	end


	def collectLinks(uri,page)
		Msg.info "#{__method__}(#{ URI::decode(uri) })"

		base_uri = URI(uri)

		all_links = []

		anchors = Nokogiri::HTML(page).xpath('//a').map { |i|
			
			i['href'].nil? and next
			i['href'].empty? and next
			
			i['href'].strip!
			href = i['href']
			#href = URI::decode(i['href'])
			#puts 'decoded href: ' + href.to_s
			
			all_links << href
		}
		
		
		www_links = []
		
		all_links.each { |item|
			
			next if item.match(/^mailto:/)
			next if item.match(/action=edit/)

			item_orig = item
			
			begin
				item = URI::decode(item)
			rescue
				Msg.alert "кривая ссылка для urldecode: #{item_orig.encode()}"
				next
			end
			
			begin
				item = URI::encode(item)
			rescue
				Msg.alert "кривая ссылка для urlencode: #{item_orig.encode()}"
				next
			end
						
			www_links << item
		}
		
		
		normalized_links = []
		
		www_links.each { |item|
		
			begin
				uri = URI(item)
			rescue
				Msg.alert "кривая ссылка ВТОРОГО уровня: #{item.encode()}"
				next
			end
		
			uri.scheme = base_uri.scheme if uri.scheme.to_s.empty?
			uri.host = base_uri.host if uri.host.to_s.empty?
		
			normalized_links << uri.to_s
		}
		
		normalized_links.compact!
		normalized_links.uniq!
		
		Msg.debug "raw #{all_links.count} / unique #{normalized_links.count}"
		#ap links
		
		return normalized_links
	end

	def filterLinks(links,filter)
		Msg.debug "#{__method__}(input: #{links.size})"

		return links if filter.size == 0

		selected_links = []

		links.each { |lnk|
			
			filter.each { |pat|
			
				res = lnk.match(pat) ? true : false
				
				#puts "#{res.to_s.upcase}: #{lnk}  [ #{pat} ]"
				
				if (res) then
					selected_links << lnk
					break
				end
			}
		}
		
		selected_links.uniq!
		Msg.debug "#{__method__}(output: #{selected_links.size})"
		#ap selected_links
		
		return selected_links
	end
	
# /html/body/table[1]/tbody/tr/td[2]/table/tbody/tr/td/table
# html body table tbody tr td table.ttxt tbody tr td table

	
	def extractBody(html_data,uri)
		Msg.debug "#{__method__}()"
		
		filter = getFilterFor(uri,mode='page')
		Msg.debug("page filter: #{filter}")
		
		res = Nokogiri::HTML(html_data).xpath(filter).first.to_s
		
		return res
	end

	def extractTitle(html_data)
		Msg.debug("#{__method__}() from " + html_data.size.to_s + "-bytes html")
		res = html_data.match(%r|<title[^>]*>(?<title>.*)<\s*/\s*title\s*>|im)
		return '* нет заголовка *' if res.nil?
		return res[:title].strip
	end

end



book = Book.new('test book',{
	:depth=>1,
	:pages=>5,
	:threads=>1,
	:db_type => 'memory'
})

#book.addSource('http://opennet.ru')
#book.addSource('https://ru.wikipedia.org/wiki/%D0%9E%D1%80%D1%83%D0%B6%D0%B5%D0%B9%D0%BD%D1%8B%D0%B9_%D0%BF%D0%BB%D1%83%D1%82%D0%BE%D0%BD%D0%B8%D0%B9')
#book.addSource('https://ru.wikipedia.org/wiki/Оружейный_плутоний')
#book.addSource('https://ru.wikipedia.org/wiki/Амёба')
book.addSource('https://ru.wikipedia.org/wiki/Союз_Советских_Социалистических_Республик')

#book.addSource('https://ru.wikipedia.org/wiki/Большевики')
#book.addSource('https://ru.wikipedia.org/wiki/Советский_народ')
#book.addSource('https://ru.wikipedia.org/wiki/СССР')
#book.addSource('https://ru.wikipedia.org/wiki/Гражданская_война_в_России')


filter1 = {
	'opennet.ru' => {
		'links' => [
			'(www\.)?opennet\.ru\/opennews\/art\.shtml\?num=[\d]+'
		],
		'pages' => {
			'\/opennet\.ru(\/)?$' => '//body/table[1]//table[1]',
			'(www\.)?opennet\.ru\/opennews\/art\.shtml\?num=[\d]+' => '//body/table[1]//table[1]',		
		}
	},
	'ru.wikipedia.org' => {
		'links' => [
			'ru\.wikipedia\.org\/wiki\/[^/:]+$',
		],
		'pages' => {
			'ru\.wikipedia\.org\/wiki\/[^/]+' => "//div[@id='content']"
		}
	}
}

book.addFilter(filter1)

start_time = Time.now
book.prepare()
book.create('test-book.epub')

Msg.info ''
Msg.info_blue "время выполнения: #{Time.now - start_time}"
