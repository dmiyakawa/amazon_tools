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

require 'rubygems'
require 'optparse'
require 'ostruct'
require 'logger'
require 'io/console'
require 'selenium-webdriver'

SCREENSHOTS_DIR = './screenshots'

module Amazon
  class Driver
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

    def save_order_history(wd, auth)
      @page_seq = 0
      @order_seq = 0

      # 購入履歴ページへ
      wd.get 'https://www.amazon.co.jp/gp/css/order-history'

      # ログイン処理
      wd.find_element(:id, 'ap_email').click
      wd.find_element(:id, 'ap_email').clear
      wd.find_element(:id, 'ap_email').send_keys auth[:email]

      wd.find_element(:id, 'ap_password').click
      wd.find_element(:id, 'ap_password').clear
      wd.find_element(:id, 'ap_password').send_keys auth[:password]

      wd.find_element(:id, 'signInSubmit-input').click

      unless wd.find_element(:xpath, "//form[@id='order-dropdown-form']/select//option[4]").selected?
        wd.find_element(:xpath, "//form[@id='order-dropdown-form']/select//option[4]").click  # 今年の注文
      end
      wd.find_element(:css, "#order-dropdown-form > span.in-amzn-btn.btn-prim-med > span > input[type=\"submit\"]").click

      # [次] ページをめくっていく
      loop do
        wd.find_element(:link_text, '利用規約')
        @page_seq += 1
        wd.save_screenshot("#{SCREENSHOTS_DIR}/page_#{format('%03d', @page_seq)}.png")
        open("#{SCREENSHOTS_DIR}/page_#{format('%03d', @page_seq)}.html", 'w') {|f|
          f.write wd.page_source
        }

        # ページ中の個々の注文を閲覧する。
        save_order(wd)

        elems = wd.find_elements(:link_text, '次へ »')
        break if elems.size == 0
        elems[0].click
      end

      # サインアウト
      wd.get 'http://www.amazon.co.jp/gp/flex/sign-out.html/ref=gno_signout'
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
      parser.banner = "Usage: #{File.basename($0)} account"
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
  def run()
    opts, logger = Main.parse_options()
    include Amazon
    if ARGV.size != 1
      puts "usage: ruby #{$PROGRAM_NAME} account"
      exit 1
    end
  
    print "password: "
    account = ARGV[0]
    password = STDIN.noecho(&:gets)
    puts
  
    wd = nil
    begin
      ad = Amazon::Driver.new
      wd = Selenium::WebDriver.for :firefox
      wd.manage.timeouts.implicit_wait = 20 # sec
      ad.save_order_history(wd, email: account, password: password)
    ensure
      wd.quit if wd
    end
  end
end

if File.basename($0) == File.basename(__FILE__)
  Main.run()
end

