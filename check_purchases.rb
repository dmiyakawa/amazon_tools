#!/usr/bin/env ruby
# -*- coding: utf-8 -*-
#
# http://qiita.com/katoy/items/2256ad7b59b8f59161cf

# 1. amazon の購入履歴を取得する。(scrennshots/* に保存される)
#   $ ruby amazon.rb email password
#
# 2. 取得した情報から、明細書(*.png) を１つの PDF にまとめたものを作成する。
#    (imagemagic の convert コマンドを使う)
#   $ convert -resize 575x823 -gravity north -background white -extent 595x842 screenshots/ord*.png 1.pdf
#
# 3. 取得した情報から、csv 形式で購入物一覧表を作成する。
#   $ ruby make-index.rb > 1.csv

require 'csv'
require 'rubygems'
require 'optparse'
require 'ostruct'
require 'logger'
require 'io/console'
require 'selenium-webdriver'

SCREENSHOTS_DIR = './screenshots'

module Amazon
  def self.instantiate(email, password=nil, logger=nil)
    if password.nil?
      print "password: "
      password = STDIN.noecho(&:gets)
      puts
    end
    driver = Amazon::Driver.new(logger)
    driver.login(email, password)
  end

  class Driver
    attr_reader :wd

    def initialize(logger=nil)
      @wd = Selenium::WebDriver.for(:firefox)
      @wd.manage.timeouts.implicit_wait = 10 # sec
      @logger = logger || Logger.new('/dev/null')
    end

    def close()
      @wd.quit
    end

    # 新しいタブで 指定された URL を開き、制御をそのタブに移す。
    def open_new_window(wd, url)
      a = wd.execute_script("var d=document,a=d.createElement('a');a.target='_blank';a.href=arguments[0];a.innerHTML='.';d.body.appendChild(a);return a", url)
      a.click
      wd.switch_to.window(wd.window_handles.last)

      wd.find_element(:link_text, '利用規約')
      yield
      wd.close
      wd.switch_to.window(wd.window_handles.last)
    end

    # 現在の画面からリンクが張られている購入明細を全て保存する。
    def save_order(wd)
      wd.find_element(:link_text, '利用規約')
      orders = wd.find_elements(:link_text, '領収書／購入明細書')
      orders.each do |ord|

        open_new_window(wd, ord.attribute('href')) do
          @order_seq += 1
          wd.save_screenshot("#{SCREENSHOTS_DIR}/order_#{format('%03d', @order_seq)}.png")
        end
      end
    end

    def login(email, password)
      @wd.get 'https://www.amazon.co.jp/gp/css/order-history'
      wait = Selenium::WebDriver::Wait.new(:timeout => 3)
      wait.until { @wd.find_element(:id, 'signInSubmit-input').displayed? }
      @wd.find_element(:id, 'ap_email').click
      @wd.find_element(:id, 'ap_email').clear
      @wd.find_element(:id, 'ap_email').send_keys email
      @logger.info("Hoge")
      @wd.find_element(:id, 'ap_password').click
      @wd.find_element(:id, 'ap_password').clear
      @wd.find_element(:id, 'ap_password').send_keys password
      # input = @wd.find_element(:id, 'signInSubmit-input')
      # input.click
      self
    end

    def contain(class_name)
      "contains(concat(' ',normalize-space(@class),' '), ' #{class_name} ')"
    end

    def run(csv=nil)
      run_single_page(csv)
      while go_next()
        run_single_page(csv)
      end
    end

    def run_single_page(csv=nil)
      logger = @logger
      orders = @wd.find_elements(:xpath, "//div[#{contain('order')}]")
      orders.each do |order|
        rows = order.find_elements(:xpath, "div[not(#{contain('order-attributes')})]")
        orderinfo_row = rows[0]
        order_inner = orderinfo_row.find_element(:xpath,
                                                 ("div/div/div"\
                                                  + "[#{contain('a-fixed-right-grid-inner')}]"))
        date = order_inner.find_element(:xpath, "div[1]/div/div[1]/div[2]/span").text
        price = order_inner.find_element(:xpath, "div[1]/div/div[2]/div[2]/span").text
        order_id = order_inner.find_element(:xpath, "div[2]/div[1]/span[2]").text
        rows[1..-1].each_with_index do |row, i|
          # Item Name, Author, Thumbnail
          item_info_div = row.find_element(:xpath,
                                           ("div/div/div/div/div/div["\
                                            + "#{contain('a-fixed-left-grid')}]"))
          item_a = item_info_div.find_element(:xpath,
                                              ("div/div[#{contain('a-col-right')}]/"\
                                               + "div[1]/a"))
          item_name = item_a.text
          item_url = item_a.attribute('href')

          puts "#{item_name} (#{item_url})"
          puts "#{date}, #{price}, #{order_id}"
          unless csv.nil?
            if i == 0
              entry = [item_name, item_url, date, price, order_id]
            else
              entry = [item_name, item_url, '', '', '']
            end
            csv << entry
          end
        end
      end
      self
    end

    def go_next()
      # "次へ" (Next) link
      last_item = @wd.find_element(:xpath, ("//ul[@class='a-pagination']"\
                                            + "/li[#{contain('a-last')}]"))
      a_lst = last_item.find_elements(:xpath, 'a')
      if a_lst.empty?
        return false
      else
        @wd.get a_lst[0].attribute('href')
        return true
      end
    end

    def logout()
      @wd.get 'http://www.amazon.co.jp/gp/flex/sign-out.html/ref=gno_signout'
      self
    end
  end
end

module Main
  module_function

  def parse_options
    opts = OpenStruct.new
    logger = Logger.new(STDERR)
    logger.level = Logger::INFO
    parser = OptionParser.new
    begin
      parser.banner = "Usage: #{File.basename($0)} email"
      parser.on('-h', '--help', 'print this message and quit.') do
        puts parser.help
        exit 0
      end
      parser.parse!
    rescue OptionParser::ParseError => e
      STDERR.puts e.message
      STDERR.puts parser.help
      exit 1
    end
    return opts, logger
  end
  def run(argv)
    opts, logger = Main.parse_options()
    include Amazon
    if argv.size != 1
      puts "usage: ruby #{$PROGRAM_NAME} email"
      return false
    end
    email = argv[0]
    ad = nil
    begin
      ad = Amazon.instantiate(email, nil, logger)
      ad.run_single_page()
    ensure
      ad.close unless ad.nil?
    end
    return true
  end
end

if File.basename($0) == File.basename(__FILE__)
  exit Main.run(ARGV)
end

