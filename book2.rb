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


module Msg

	def msg_debug(arg)
		#puts arg.to_s.white + 10.chr
	end

	def msg_info(arg)
		puts arg.to_s + 10.chr
	end

	def msg_error(arg)
		@errors_count += 1
		arg = arg.to_s
		puts ("ОШИБКА: " + arg).red + 10.chr
		File.open(@error_log,'w') if not File.exists?(@error_log)
		File.open(@error_log,'a') { |file| file.write(arg+10.chr) }
	end
	
	def msg_alert(arg)
		@alerts_count += 1
		arg = arg.to_s
		puts ("###: " + arg).yellow + 10.chr
		File.open(@alert_log,'w') if not File.exists?(@alert_log)
		File.open(@alert_log,'a') { |file| file.write(arg+10.chr) }
	end
	
	def msg_info_blue(arg)
		puts arg.to_s.blue + 10.chr
	end
	
	def msg_info_green(arg)
		puts arg.to_s.green + 10.chr
	end
	
	def msg_info_cyan(arg)
		puts arg.to_s.cyan + 10.chr
	end
	
	def msg_ahtung(arg)
		puts arg.to_s.black.on_yellow + 10.chr
	end
end

class String
	def urlencoded?
		return true if self.match(/[%0-9ABCDEF]{3,}/i)
		return false
	end
end

class Book

	include Msg

	attr_accessor :title, :author
	
	# методы первого уровня
	public

	# настроить
	def initialize(title,options={})

		msg_info "#{__method__}('#{title}','#{author}')"
		
		@user_agent = 'Ruby/1.9.3, Contacts: aakumykov@yandex.ru'

		# свойства книги
		self.title = title.to_s.strip
		self.author = author.to_s.strip.empty? ? 'неизвестный автор' : author

		# каталоги
		@@script_name = File.basename(File.realpath(__FILE__)).split('.')[0]
		@work_dir = Dir.tmpdir + '/' + @@script_name
		Dir.mkdir(@work_dir) if not Dir.exists?(@work_dir)
		msg_debug("work_dir: #{@work_dir}")

		@book_dir = @work_dir + '/' + self.title.gsub(/\s/,'_')
		Dir.mkdir(@book_dir) if not Dir.exists?(@book_dir)
		
		# удаляю старые файлы
		Dir.new(@book_dir).each { |item| File.delete "#{@book_dir}/#{item}" if item.match(/\.html/) }
		
		# журнал ошибок
		@error_log = "errors-#{@@script_name}.log"
		@alert_log = "alerts-#{@@script_name}.log"
		
		File.delete(@error_log) if File.exists?(@error_log)
		File.delete(@alert_log) if File.exists?(@alert_log)
		
		# рабочие параметры
		@threads = 1
		@threads = options[:threads].to_i if not options[:threads].nil?

		@options = {}
		@filters = {}
		
		@current_depth = 0
		@target_depth = 0
		@target_depth = options[:depth].to_i if not options[:depth].nil?
		
		@page_count = 0 
		@page_limit = 0		# 0 (zero) disables this limit
		@page_limit = options[:total_pages].to_i if not options[:total_pages].nil?
		
		@pages_per_level = 0 # 0 == unlimited
		@pages_per_level = options[:pages_per_level] if not options[:pages_per_level].nil?
		
		# параметр нужен на период тестирования для ограничения нагрузки на файловую БД
		@links_per_level = 0 # 0 == unlimited
		@links_per_level = options[:links_per_level] if not options[:links_per_level].nil?
		
		@errors_count = 0
		@errors_limit = 100
		
		@alerts_count = 0 # только для информации
		@alerts_limit = 0 # пока не используется
		
		@timeout_limit = 60
		
		case options[:db_type] 
		when 'f'
			@db_name = 'db_' + @@script_name + '.sqlite'
		else
			@db_name = ':memory:'
		end
		
		@table_name = 'book_info'

		table_def = <<QWERTY
CREATE TABLE #{@table_name} 
(
	id TEXT PRIMARY KEY,
	parent_id TEXT,
	depth INT,
	status TEXT,
	uri TEXT,
	archor_name TEXT,
	title TEXT,
	file TEXT
)
QWERTY

		@db = SQLite3::Database.new(@db_name)
		
		@db.results_as_hash = true
		
		@db.query("PRAGMA journal_mode=OFF")
		
		@db.query("DROP TABLE IF EXISTS #{@table_name}")
		
		@db.query(table_def)
	end

	def addSource(uri)
		msg_info "#{__method__}(#{uri})"
				
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
		msg_info "#{__method__}(#{filter.keys})"
		
		@filters.merge!(filter)
		
		#pp @filters
	end

	def prepare()
		
		msg_info "#{__method__}()"
		
		# пока не будет готово
		#until ( prepareComplete? ) do
		while ( not prepareComplete? ) do
				
			msg_debug "CURRENT: pages #{@page_count}, depth #{@current_depth}"
			
			# брать порцию ссылок
			links = getFreshLinks(@current_depth, @threads)
			
			# и обрабатывать (в потоках)
			threads = []
			
			links.each { |row|

				source_id = row['id']
				source_uri = row['uri']
				
				# зарядить нить обработки
				threads << Thread.new(source_uri) { |uri|

					# получишь страницу
					source_page = loadPage(uri)
					
					# выделишь заголовок
					page_title = extractTitle(source_page)
					msg_info_green "заголовок: #{page_title}"
					
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
					
					setLinkStatus(source_id,{:status=>'processed',:title=>page_title})
					
					@page_count += 1
				}
			}
			
			# запустить обработку в нитях
			threads.each { |thr| thr.join }
		
			displayStatus
			
			@current_depth += 1 if not freshLinksExists?(@current_depth)

			if depthComplete?(@current_depth) then
				msg_info_green "на уровне #{@current_depth} обработаны все страницы (#{@pages_per_level})"
				@current_depth += 1
			end
			
			# пауза перед следующей порцией
			if @threads > 5 then
				print "Ждём 5 секунд";
				4.times { sleep 1 and print '.' };
				sleep 1 and puts '.'
			end
			
			puts ""
		end		
		
	end
	
	def getBookStructure
		msg_debug "#{__method__}()"
		
		def getTocItems(id)
			list = []
			res = @db.prepare("SELECT * FROM #{@table_name} WHERE parent_id=? AND status='processed'").execute(id)
			res.each { |row|
				list << {
					:id => row['id'],
					:title => row['title'],
					:file => row['file'],
					:uri => row['uri'],
					:childs => getTocItems(row['id'])
				}
			}
			return list
		end

		res = @db.query("SELECT * FROM #{@table_name} WHERE depth=0 AND status='processed'")
		raise "пустое оглавление" if 0 == res.count
		
		res.reset # ВАЖНО, сброс курсора после 'res.count'
		root_id = res.next['id']

		return getTocItems(root_id)
	end
	
	def create(file='')
		msg_info "#{__method__}(#{file})"
		
		bookArray = getBookStructure
		
		CreateEpub(
			{ :title=>@title, :author=>@author },
			bookArray
		)
	end


	private
	
	def prepareComplete?
	
		#return @current_depth == @target_depth
		
		if  not freshLinksExists?(@current_depth) then
			reason = "все ссылки обработаны"
		
		elsif @current_depth > @target_depth then
			reason = "достигнута глубина #{@target_depth}"
		
		elsif @errors_count > @errors_limit then
			reason = "достигнут максимум ошибок (#{@errors_limit})"
		
		elsif ( @page_count >= @page_limit) and (0 != @page_limit)  then
			reason = "достигнут максимум страниц (#{@page_limit})"
		
		else
			return false
		end

		return true
	end

	def freshLinksExists?(depth)
		#msg_debug "#{__method__}(#{depth})"
		
		q = "SELECT * FROM #{@table_name} WHERE depth='#{depth}' AND status='fresh'"
		res = @db.execute(q)
		res = res.count != 0
		
		#msg_debug  "#{__method__}(depth #{depth}) ==> #{res}"
		
		return res
	end

	def depthComplete?(depth)
		msg_debug "#{__method__}()"
		
		q = "SELECT  * FROM #{@table_name} WHERE depth=? AND status='processed' "
		
		res = @db.prepare(q).execute(depth)
		
		return ( res.count >= @pages_per_level and 0 != @pages_per_level )
	end

	def getFreshLinks ( depth, amount )
		msg_info "#{__method__}(#{depth},#{amount})"
		
		q = "SELECT * FROM #{@table_name} WHERE status='fresh' AND depth=#{depth} LIMIT #{amount}"
		res = @db.execute(q)
		
		#res.each { |row| msg_info "#{row['uri']}" }
		
		return res
	end
	
	def loadPage(uri)
		msg_info_blue "#{__method__}('#{uri.urlencoded? ? URI::decode(uri) : uri}')"
		
		curl = CURL.new
		curl.user_agent = @user_agent
		page = curl.get(uri)

		return page
	end
	
	def extractLinks(html_data,uri,filter='')
		msg_debug "#{__method__} from page '#{uri}'"
		
		links = collectLinks(uri,html_data)
		#puts "collected: #{links.size}"
		
		filter = getFilterFor(uri,'links')
		
		links = filterLinks(links,filter)
		#links.each { |lnk| puts URI::decode(lnk) }

		return links
	end
	
	def saveLink(id, parent_id, depth, uri)
		#msg_info "#{__method__}(#{id}, #{parent_id}, #{depth}, #{uri})"
		#msg_info "#{__method__}(#{uri})"
		
		uri = URI::encode(uri) if not uri.urlencoded?
		
		q_check = "SELECT * FROM #{@table_name} WHERE uri = ?"
		res = @db.prepare(q_check).execute(uri)
		
		if res.count > 0 then
			msg_debug "Дубликат #{uri}"
			return false
		end
		
		q = "INSERT INTO #{@table_name} (id, parent_id, depth, status, uri) VALUES (?, ?, ?, ?, ?)"
		
		begin
			@db.prepare(q).execute(
				id,
				parent_id,
				depth,
				'fresh',
				uri
			)
		rescue
			msg_error "'#{q}'"
		end
	end
	
	def savePage(arg)
		id = arg[:id]
		title = arg[:title]
		page_body = arg[:body]
		
		file_name = @book_dir+"/"+arg[:id]+".html"
		
		msg_info "#{__method__}('#{title}', '#{file_name}'), body size: #{page_body.size}"

		begin
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
		rescue
			msg_error "запись #{title} в файл #{file_name}"
		end
		
		begin
			q = "UPDATE #{@table_name} SET file='#{file_name}' WHERE id='#{id}'"
			@db.query(q)
		rescue
			msg_error "сохранение в БД имени файла (#{file_name}) для '#{title}'"
		end
	end
	
	def setLinkStatus(id,options)
		msg_info "#{__method__}(), #{options[:title]}, #{options[:status]}, #{id}"
		
		q = "UPDATE #{@table_name} SET status='#{options[:status]}', title='#{options[:title]}' WHERE id='#{id}'"
		
		# писать в БД до победного конца (что-то пошли дедлоки)
		res = nil
		while res.nil? do
			begin
				res = @db.prepare(q).execute()
			rescue => e
				msg_error e.message
			end
		end
	end
	
	
	# методы второго уровня
	def getOptions(id)
		msg_debug "#{__method__}(#{id})"
		
		if @options.has_key?(id) then
			return @options[id]
		else
			return {}
		end
	end

	def getFilterFor(uri,mode)
		msg_debug "#{__method__}(#{uri},'#{mode}')"
		
		host = URI(uri).host
		
		case mode
			when 'links'
				msg_debug "items in filter: #{@filters[host]['links'].size}"
				
				return @filters[host]['links']

			when 'page'
				@filters[host]['pages'].each { |pattern,rule|
					return rule if uri.match(pattern) 
				}
				return '/'

			else
				msg_error "неизвестный режим '#{mode}'"
				return nil
		end
	end


	def collectLinks(uri,page)
		msg_info "#{__method__}(#{ URI::decode(uri) })"

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
		
		count = 0
		all_links.each { |item|
		
			break if @links_per_level != 0 and count > @links_per_level
			
			next if item.match(/^mailto:/)
			next if item.match(/action=edit/)

			item_orig = item
			
			begin
				item = URI::decode(item)
			rescue
				msg_alert "кривая ссылка для urldecode: #{item_orig.encode()}"
				next
			end
			
			begin
				item = URI::encode(item)
			rescue
				msg_alert "кривая ссылка для urlencode: #{item_orig.encode()}"
				next
			end
						
			www_links << item
			
			count += 1
		}
		
		
		normalized_links = []
		
		www_links.each { |item|
		
			begin
				uri = URI(item)
			rescue
				msg_alert "кривая ссылка ВТОРОГО уровня: #{item.encode()}"
				next
			end
		
			uri.scheme = base_uri.scheme if uri.scheme.to_s.empty?
			uri.host = base_uri.host if uri.host.to_s.empty?
		
			normalized_links << uri.to_s
		}
		
		normalized_links.compact!
		normalized_links.uniq!
		
		msg_debug "raw #{all_links.count} / unique #{normalized_links.count}"
		#ap links
		
		return normalized_links
	end

	def filterLinks(links,filter)
		msg_debug "#{__method__}(input: #{links.size})"

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
		msg_debug "#{__method__}(output: #{selected_links.size})"
		#ap selected_links
		
		return selected_links
	end
	
# /html/body/table[1]/tbody/tr/td[2]/table/tbody/tr/td/table
# html body table tbody tr td table.ttxt tbody tr td table

	
	def extractBody(html_data,uri)
		msg_debug "#{__method__}()"
		
		filter = getFilterFor(uri,mode='page')
		msg_debug("page filter: #{filter}")
		
		res = Nokogiri::HTML(html_data).xpath(filter).first.to_s
		
		return res
	end

	def extractTitle(html_data)
		msg_debug("#{__method__}() from " + html_data.size.to_s + "-bytes html")
		res = html_data.match(%r|<title[^>]*>(?<title>.*)<\s*/\s*title\s*>|im)
		return '* нет заголовка *' if res.nil?
		return res[:title].strip
	end

	def displayStatus
		msg_info_blue "====  глубина #{@current_depth}===="
		msg_info_blue "==== страниц #{@page_count}===="
		msg_info_blue "==== ошибок #{@errors_count}===="
		msg_info_blue "==== предупреждений #{@alerts_count}===="
	end


	def CreateEpub (metadata, bookArray)
		msg_info "#{__method__}()"
=begin
		def MakeNcx(bookArray)
				msg_info "#{__method__}()"
				
				data = ''
				
				bookArray.each { |item|
					
					id = Digest::MD5.hexdigest(item[:id])
					playOrder = item[:id]
					
					data += <<NAVPOINT
	<navPoint id='#{id}' playOrder='#{playOrder}'>
		<navLabel>
			<text>#{item[:title]}</text>
		</navLabel>
		<content src='#{item[:file]}'/>
NAVPOINT
					if not item[:childs].nil? then
						data += MakeNcx(item[:childs])
					end
					
					data += "\n</navPoint>"
				}
			end
		end
		
		def MakeOpf
		
		end
		
		ncxData = MakeNcx()
		#opfData = MakeOpf()
=end	
	end


end

book = Book.new('test book',{
	:depth => 5,
	:threads => 1,
	:total_pages => 3,
	:pages_per_level => 2,
	:links_per_level => 5,
	:db_type => 'f'
})

#book.addSource('http://opennet.ru')
#book.addSource('https://ru.wikipedia.org/wiki/%D0%9E%D1%80%D1%83%D0%B6%D0%B5%D0%B9%D0%BD%D1%8B%D0%B9_%D0%BF%D0%BB%D1%83%D1%82%D0%BE%D0%BD%D0%B8%D0%B9')
#book.addSource('https://ru.wikipedia.org/wiki/Оружейный_плутоний')
book.addSource("https://ru.wikipedia.org/wiki/Оргазм")

# ================ ДЛЯ ПРОВЕРОК ===============
# для проверки ожидания...
#book.addSource('http://www.tldp.org/HOWTO/archived/IP-Subnetworking/IP-Subnetworking-1.html')

##
## Глюк
##
#~ book.addSource('https://ru.wikipedia.org/wiki/Амёба')
#~ book = Book.new('test book',{
	#~ :depth => 2,
	#~ :threads => 25,
	#~ :db_type => 'm'
#~ })

##
## на Сенеке, предположительно, в вывод через <title> лезет HTML-код
##
#~ book.addSource('https://ru.wikipedia.org/wiki/Галльская_война')
#~ book.addSource('https://ru.wikipedia.org/wiki/55_до_н._э.')
#~ book.addSource('https://ru.wikipedia.org/wiki/54_до_н._э.')
#~ book.addSource('https://ru.wikipedia.org/wiki/Римское_завоевание_Британии')
#~ book.addSource('https://ru.wikipedia.org/wiki/Римская_империя')
#~ book.addSource('https://ru.wikipedia.org/wiki/Публий_Корнелий_Тацит')
#~ book.addSource('https://ru.wikipedia.org/wiki/Ювенал')
#~ book.addSource('https://ru.wikipedia.org/wiki/III_век')
#~ book.addSource('https://ru.wikipedia.org/wiki/VI_век')
#~ book.addSource('https://ru.wikipedia.org/wiki/Иероним_Стридонский')
#~ book.addSource('https://ru.wikipedia.org/wiki/Тридентский_собор')
#~ book.addSource('https://ru.wikipedia.org/wiki/Эпоха_Возрождения')
#~ book.addSource('https://ru.wikipedia.org/wiki/Рейн_(река)')
#~ book.addSource('https://ru.wikipedia.org/wiki/Юлий_Цезарь')
#~ book.addSource('https://ru.wikipedia.org/wiki/43')
#book.addSource('https://ru.wikipedia.org/wiki/476')
#~ book.addSource('https://ru.wikipedia.org/wiki/407')
#~ book.addSource('https://ru.wikipedia.org/wiki/Апулей')
#~ book.addSource('https://ru.wikipedia.org/wiki/Везалий,_Андреас')
#~ book.addSource('https://ru.wikipedia.org/wiki/Древние_германцы')
#~ book.addSource('https://ru.wikipedia.org/wiki/Сенека')
#~ book.addSource('https://ru.wikipedia.org/wiki/Марциал')
#~ book.addSource('https://ru.wikipedia.org/wiki/1543')
#~ book.addSource('https://ru.wikipedia.org/wiki/Историк')
#~ book.addSource('https://ru.wikipedia.org/wiki/Великобритания')

##
## кривое поведение на этой:
##
# book.addSource('https://ru.wikipedia.org/wiki/476')

# ================ ДЛЯ ПРОВЕРОК ===============


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

puts ''
puts "время выполнения: #{Time.now - start_time}"
