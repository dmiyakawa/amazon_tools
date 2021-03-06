#!/usr/bin/env ruby
# -*- coding: utf-8 -*-
#
# See README.md for instructions
#

require 'csv'
require 'rubygems'
require 'optparse'
require 'ostruct'
require 'logger'
require 'io/console'
require 'selenium-webdriver'

module Amazon
  module_function

  def self.instantiate(email, password=nil, opts=nil, logger=nil)
    if password.nil?
      $stderr.print "password for \"#{email}\": "
      $stderr.flush()
      password = $stdin.noecho(&:gets)
      $stderr.puts
      $stderr.flush()
    end
    Amazon::Driver.new(email, password, opts, logger)
  end

  class Driver
    attr_reader :wd

    def initialize(email, password, opts=nil, logger=nil)
      @opts = opts || OpenStruct.new
      @logger = logger || Logger.new('/dev/null')

      @wd = Selenium::WebDriver.for(:firefox)
      @wd.manage.timeouts.implicit_wait = opts.implicit_wait
      @wd.get('https://www.amazon.co.jp/gp/css/order-history')
      wait = Selenium::WebDriver::Wait.new(:timeout => 3)
      wait.until do
        displayed = false
        begin
          displayed = @wd.find_element(:name, 'signIn').displayed?
        rescue Selenium::WebDriver::Error::NoSuchElementError
        end
        unless displayed
          displayed = @wd.find_element(:id, 'signInSubmit-input').displayed?
        end
        displayed
      end
      @wd.find_element(:id, 'ap_email').click
      @wd.find_element(:id, 'ap_email').clear
      @wd.find_element(:id, 'ap_email').send_keys(email)
      @wd.find_element(:id, 'ap_password').click
      @wd.find_element(:id, 'ap_password').clear
      @wd.find_element(:id, 'ap_password').send_keys(password)
      self
    end

    def each
      fail unless @wd
      return to_enum(:each) unless block_given?

      scan_all_pages do |order_struct|
        yield order_struct
      end
      release()
    end
    
    def release()
      unless @wd
        @wd.quit()
        @wd = nil
      end
    end

    def contain(class_name)
      "contains(concat(' ',normalize-space(@class),' '), ' #{class_name} ')"
    end

    def scan_all_pages(csv=nil, &block)
      scan_single_page(csv, &block)
      while go_next()
        scan_single_page(csv, &block)
      end
    end

    def scan_single_page(csv=nil)
      logger = @logger

      orders = @wd.find_elements(:xpath, "//div[#{contain('order')}]")
      orders.each_with_index do |order, order_i|
        logger.debug("Start scanning element #{order_i+1}/#{orders.size}")
        order_struct = OpenStruct.new

        begin
          # それぞれ
          # <div class="a-box-group a-spacing-base order">
          # のようなdivに囲われている。
          # これ以降ヒントに出来るidが存在しないので、力技。
          # 連続する子のdiv要素のindex 0は注文日、合計
          rows = order.find_elements(
            :xpath, "div[not(#{contain('order-attributes')})]")
          orderinfo_row = rows[0]
          order_inner = orderinfo_row.find_element(
            :xpath, "div/div/div[#{contain('a-fixed-right-grid-inner')}]")
          
          date_str = order_struct.date_str = order_inner.find_element(
            :xpath, "div[1]/div/div[1]/div[2]/span").text
          # ギフトーカード割引等の適用後の値段。
          # 各商品の価格の総和ではない
          paid_price = order_struct.paid_price = order_inner.find_element(
            :xpath, "div[1]/div/div[2]/div[2]/span").text
          order_id = order_struct.order_id = order_inner.find_element(
            :xpath, "div[2]/div[1]/span[2]").text

          m = date_str.match(/(\d{4})年(\d{1,2})月(\d{1,2})日/)
          unless m
            fail "Unexpected date format (#{date_str})"
          end
          date = order_struct.date = Date.new(m[1].to_i, m[2].to_i, m[3].to_i)
          if @opts.drop_before && date < @opts.drop_before
            logger.debug("Ignoring order #{order_id} (#{date} < #{@opts.drop_before})")
            next
          end
          if @opts.drop_after && @opts.drop_after < date
            logger.debug("Ignoring order #{order_id} (#{@opts.drop_after} < #{date})")
            next
          end

          rows[1..-1].each_with_index do |row, row_i|
            # アイテム名、サムネイルなどをまとめたdiv要素。
            # ひとつの注文の中に複数ある可能性がある。
            item_info_row_divs = row.find_elements(
              :xpath,
              "div/div/div/div/div/div[#{contain('a-fixed-left-grid')}]/div")
            item_info_row_divs.each do |item_info_row_div|
              # left_columnはサムネイル画像
              right_column = item_info_row_div.find_element(
                :xpath, "div[#{contain('a-col-right')}]")
              # 右カラムの1行めが商品名。
              # 商品へのリンクが貼られることが多いが、例えばAndroidアプリではリンクがない
              item_name_div = right_column.find_element(:xpath, "div[1]")
              item_name = order_struct.item_name = item_name_div.text
              item_url = order_struct.item_url = nil
              begin
                item_a = item_name_div.find_element(:xpath, "a")
                item_url = order_struct.item_url = item_a.attribute('href')
              rescue Selenium::WebDriver::Error::WebDriverError
                logger.debug("Failed to fetch url")
              end

              price = order_struct.price = ''
              begin
                # 0円でない商品であれば商品価格が併せて表示される
                item_price_div = right_column.find_element(
                  :xpath, "div/span[#{contain('a-color-price')}]")
                price = order_struct.price = item_price_div.text
              rescue Selenium::WebDriver::Error::WebDriverError
                logger.debug("Failed to fetch price information")
              end
              if block_given?
                yield order_struct
              end
            end
          end
        rescue Selenium::WebDriver::Error::WebDriverError => exception
          logger.error( "WebDriverdError raised: #{exception}" )
          exception.backtrace.each { |e_line| logger.error( e_line ) }
          raise unless @opts.force
        end
      end
      self
    end

    def go_next()
      # "次へ" (Next) link
      last_item = @wd.find_element(
        :xpath, "//ul[@class='a-pagination']/li[#{contain('a-last')}]")
      a_lst = last_item.find_elements(:xpath, 'a')
      if a_lst.empty?
        return false
      else
        @wd.get a_lst[0].attribute('href')
        return true
      end
    end

    def logout()
      @wd.get('http://www.amazon.co.jp/gp/flex/sign-out.html/ref=gno_signout')
      self
    end
  end
end

module Main
  module_function

  def parse_options
    opts = OpenStruct.new
    opts.implicit_wait = 5  # sec
    logger = Logger.new($stderr)
    logger.level = Logger::WARN
    logger.formatter = proc do |severity, time, _progname, msg|
      severity_s = sprintf("%5s", severity)
      pid_s = sprintf("#%5d", Process.pid)
      time_s = time.strftime("%Y-%m-%d %H:%M:%S")
      "#{severity_s} #{pid_s} #{time_s}  #{msg}\n"
    end
    parser = OptionParser.new
    begin
      parser.banner = "Usage: #{File.basename($0)} email"
      parser.on('-h', '--help', 'print this message and quit.') do
        $stderr.puts parser.help
        exit 0
      end
      parser.on('-l LEVEL', '--log-level LEVEL', 'debug level') do |level|
        case level
        when "DEBUG"
          logger.level = Logger::DEBUG
        when "INFO"
          logger.level = Logger::INFO
        when "WARN"
          logger.level = Logger::WARN
        when "ERROR"
          logger.level = Logger::ERROR
        when "FATAL"
          logger.level = Logger::FATAL
        else
          fail "Unknown log level \"#{level}\""
        end
      end
      parser.on('-b', '--drop-before DATE') do |d|
        opts.drop_before = Date.parse(d)
      end
      parser.on('-a', '--drop-after DATE') do |a|
        opts.drop_after = Date.parse(d)
      end
      parser.on('-f', '--force', 'Force proceed on error') do
        opts.force = true
      end
      parser.on('-p', '--prepare', 'Allow a user to prepare after login') do
        opts.prepare = true
      end
      parser.on('-w', '--implicit-wait SEC',
                'Wait time on searching for elements (unit: sec)') do |sec|
        opts.implicit_wait = sec
      end
      parser.on('--verbose-csv') do
        opts.verbose_csv = true
      end
      parser.parse!
    rescue OptionParser::ParseError => e
      $stderr.puts e.message
      $stderr.puts parser.help
      exit 1
    end
    opts.freeze()
    return opts, logger
  end

  def run(argv)
    opts, logger = Main.parse_options()
    if argv.size != 1
      $stderr.puts "usage: ruby #{$PROGRAM_NAME} email"
      $stderr.flush()
      return false
    end
    email = argv[0]
    ad = Amazon.instantiate(email, nil, opts, logger)
    begin
      if opts.prepare
        $stderr.print "Press Enter when ready."
        $stderr.flush()
        $stdin.gets
      end
      $stdout.sync = true
      CSV do |csv|
        prev_date = nil
        prev_order_id = nil
        ad.each.with_index do |os, i|
          logger.debug("date: #{os.date}")
          logger.debug("order_id: \"#{os.order_id}\"")
          logger.debug("item_name: \"#{os.item_name}\"")
          logger.debug("price: #{os.price}")
          logger.debug("paid_price: #{os.paid_price}")
          logger.debug("url: #{os.item_url}")
          if i == 0
            csv << ['Date', 'Order ID', 'Name',
                    'Item Price','Paied Price', 'Item URL']
          end
          csv << [os.date, os.order_id, os.item_name,
                  os.price, os.paid_price, os.item_url]
          prev_date = os.date
          prev_order_id = os.order_id
        end
      end
    rescue
      ad.release() if ad
      raise
    end
    return true
  end
end

if File.basename($0) == File.basename(__FILE__)
  exit Main.run(ARGV)
end

