# -*- coding: utf-8 -*-

require 'selenium-webdriver'

module Plugin::Mikuttdeck

  Error = Class.new(StandardError)

  # Selenium::WebDriver のラッパークラス。メソッドの呼び出しは Deferred される
  class DriverProxy

    attr_reader :thread

    def initialize(browser, option = {}, url)
      @thread = SerialThreadGroup.new(deferred: Deferred)

      @driver = parallel do
        driver = Selenium::WebDriver.for browser, option
        driver.get(url)
        # TweetDeckが読み込み終わるまで待つ
        sleep 4
        driver
      end
    end

    def method_missing(name, *args, &blk)
      thread.new do
        @driver.__send__(name, *args, &blk)
      end
    end

    def respond_to_missing?(name, include_private)
      @driver.respond_to?(name, include_private)
    end
  end

  class Deck

    def initialize(browser, option = {})
      @driver = DriverProxy.new(browser, option, 'https://tweetdeck.twitter.com')
      @status = :initialized
    end

    def start
      Deferred.new do
        if @status == :initialized
          @status = :starting
          +@driver.find_element(:id, 'container').trap {|e|
            case e
            when Selenium::WebDriver::Error::NoSuchElementError
              Deferred.fail(Error.new('mikuttdeck: TweetDeckにログインしていないようです。'))
            else
              Deferred.fail(e)
            end
          }
          columns = (+self.columns).select{|c| c.type == :home_timeline }
          if columns.empty?
            raise Error, Plugin[:mikuttdeck]._(
              'mikuttdeck: TweetDeckでつかえるカラムが開かれてないようです。' \
                'mikutterにログインしているのと同じアカウントでログインし、Homeカラムを開いてください。'
            )
          end
          @columns = columns
          refresh
          @status = :running
        else
          raise Error, Plugin[:mikuttdeck]._('mikuttdeck state error')
        end
      end
    end

    def refresh
      Deferred.new do
        fetch
      end
      Reserver.new(4) do
        Deferred.new do
          refresh
        end
      end
    end

    def fetch
      @columns.each do |column|
        ids = +@driver.execute_script(
          file_get_contents(File.expand_path(File.join(File.dirname(__FILE__), 'home_timeline.js'))),
          column.element,
          column.latest
        )
        column.latest = ids.first
        messages = +((column.service.twitter/'statuses/lookup').messages(id: ids.join(',')))
        Plugin.call(:update, column.service, messages)
        Plugin.call(:mention, column.service, messages.select{ |m| m.to_me? })
        Plugin.call(:mypost, column.service, messages.select{ |m| m.from_me? })
        messages
      end
    end
  
    def columns
      Deferred.new do
        (+@driver.find_elements(:css,
          '#column-navigator > div.js-column-nav-list > ul.js-int-scroller > li.column-nav-item'
        )).map do |e|
          data_column = +@driver.thread.new do e.attribute('data-column') end
          element = +@driver.find_element(:css,
            "#container > div.app-columns > section.column[data-column=#{ data_column }] > div.column-holder" \
              " > div.column-panel > div.column-content > div.column-scroller > div.chirp-container"
          )
          type = (+@driver.thread.new do
            e.find_element(:css, 'a.column-nav-link > div.js-column-title > span.column-heading')
          end).text
          type = case type
            when 'Home'
              :home_timeline
            when 'Notifications'
              :notifications
            else
              type
            end
          screen_name = (+@driver.thread.new do
            e.find_element(
              :css, 'a.column-nav-link > div.js-column-title > span.attribution'
            )
          end).text.delete_prefix('@')
          Column.new(element, type, screen_name)
        end.select {|c| c.service }
      end
    end

    def close
      @driver.close.next {
        @status = :closed
      }
    end
  end

  class Deck::Column < Struct.new(:element, :type, :service, :latest)
    class << self
      def new(element, type, screen_name)
        service = Service.instances.find do |s|
          s.user_obj.idname == screen_name
        end
        super(element, type, service, nil)
      end
    end
  end
end

Plugin.create(:mikuttdeck) do

  def start
    if UserConfig[:mikuttdeck_browser].empty?
      activity :system, _(
        'mikuttdeck: ブラウザが設定されていません。設定ダイアログでブラウザを設定して、その後mikuttdeckを有効にし直してください。'
      )
      return Deferred.new
    end
    Deferred.new do
      @deck = Plugin::Mikuttdeck::Deck.new(
        UserConfig[:mikuttdeck_browser].downcase.to_sym,
        UserConfig[:mikuttdeck_selenium_option] || {}
      )
      @deck.start.trap {|e|
        #case e
        #when Plugin::Mikuttdeck::Error
          activity :system, e.message
        #else
        #  Deferred.trap(e)
        #end
      }
    end
  end

  def stop
    if @deck
      @deck.close
      @deck = nil
    end
  end

  settings(_('mikuttdeck')) do
    boolean(_('mikuttdeckを有効にする'), :mikuttdeck_enable)
    input(_('ブラウザ'), :mikuttdeck_browser)
  end

  on_userconfig_modify do |key, newval|
    if key == :mikuttdeck_enable
      if newval then start else stop end
    end
  end

  start if UserConfig[:mikuttdeck_enable]
end
