#!/usr/bin/env ruby
# -*- coding: utf-8 -*-
#
# pry> require_relative('check_purchases.rb')
# pry> driver = Amazon.instantiate('(your login account name here)')
# (enter your account password)
# ("Manually" check login and select which range you want to use)
# pry> csv = CSV.open('path-to-csv')
# pry> driver.run(csv)
# ...
# => nil
# (you are done)
#

require 'csv'
require 'rubygems'
require 'optparse'
require 'ostruct'
require 'logger'
require 'io/console'
require 'selenium-webdriver'

module Amazon
  def self.instantiate(email, password=nil, opts=nil, logger=nil)
    if password.nil?
      print "password: "
      password = STDIN.noecho(&:gets)
      puts
    end
    driver = Amazon::Driver.new(opts, logger)
    driver.login(email, password)
  end

  class Driver
    attr_reader :wd

    def initialize(opts=nil, logger=nil)
      @wd = Selenium::WebDriver.for(:firefox)
      @wd.manage.timeouts.implicit_wait = 10 # sec
      @opts = opts || OpenStruct.new
      @logger = logger || Logger.new('/dev/null')
    end

    def close()
      @wd.quit
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
        rows = order.find_elements(
          :xpath, "div[not(#{contain('order-attributes')})]")
        orderinfo_row = rows[0]
        order_inner = orderinfo_row.find_element(
          :xpath, "div/div/div[#{contain('a-fixed-right-grid-inner')}]")
        date = order_inner.find_element(
          :xpath, "div[1]/div/div[1]/div[2]/span").text
        price = order_inner.find_element(
          :xpath, "div[1]/div/div[2]/div[2]/span").text
        order_id = order_inner.find_element(
          :xpath, "div[2]/div[1]/span[2]").text
        rows[1..-1].each_with_index do |row, i|
          # Item Name, Author, Thumbnail
          item_info_div = row.find_element(
            :xpath, "div/div/div/div/div/div[#{contain('a-fixed-left-grid')}]")
          item_a = item_info_div.find_element(
            :xpath, "div/div[#{contain('a-col-right')}]/div[1]/a")
          item_name = item_a.text
          item_url = item_a.attribute('href')

          logger.info("#{item_name} (#{item_url})")
          logger.info("#{date}, #{price}, #{order_id}")
          unless csv.nil?
            if i == 0
              entry = ['Date', 'ID', 'Name', 'Price']
              entry << 'URL' if @opts.include_url
            end
            entry = [date, order_id, item_name, price]
            entry << item_url if @opts.include_url
            csv << entry
          end
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
    logger = Logger.new(STDERR)
    logger.level = Logger::INFO
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
        puts parser.help
        exit 0
      end
      parser.parse!
    rescue OptionParser::ParseError => e
      STDERR.puts e.message
      STDERR.puts parser.help
      exit 1
    end
    opts.freeze
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
      ad = Amazon.instantiate(email, nil, opts, logger)
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

