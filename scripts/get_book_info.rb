require 'nokogiri'
require 'mechanize'
require 'json'
require 'pry'

class ::Hash
  # via https://stackoverflow.com/a/25835016/2257038
  def stringify_keys
    h = map do |k, v|
      v_str = if v.instance_of? Hash
                v.stringify_keys
              else
                v
              end

      [k.to_s, v_str]
    end
    Hash[h]
  end

  # via https://stackoverflow.com/a/25835016/2257038
  def symbol_keys
    h = map do |k, v|
      v_sym = if v.instance_of? Hash
                v.symbol_keys
              else
                v
              end

      [k.to_sym, v_sym]
    end
    Hash[h]
  end
end

class GetBookInfo
  attr_accessor :audible_path, :audible_page, :amazon_path, :amazon_page, :agent, :review_page,
                :review_page_state_object, :finished

  def initialize(url, finished)
    @url = url
    @finished = finished
  end

  def call
    create_scraping_agent
    extract_from_audible
    puts [output_data.stringify_keys].to_yaml
  end

  private

  def create_scraping_agent
    @agent = Mechanize.new { |agent| agent.user_agent = user_agent }
  end

  def extract_from_audible
    @audible_path = @url.split('?')[0]
    get_audible_page
    get_amazon_review_page
    extract_amazon_page_link_from_audible
    get_amazon_page
  end

  def get_audible_page
    @audible_page = Nokogiri::HTML(agent.get(audible_path).body)
    puts 'Pause after getting audible page (to sneak past the amazon anti-scraping guards)'
    sleep(rand(1.0..3.0))
    puts 'Resuming...'
  end

  def get_amazon_review_page
    review_path = 'https://' + URI.parse(audible_path).host + audible_page.css('#adbl-amzn-portlet-reviews').attribute('src').value
    @review_page = Nokogiri::HTML(agent.get(review_path).body)
    puts 'Pause after getting review page (to sneak past the amazon anti-scraping guards)'
    sleep(rand(1.0..3.0))
    puts 'Resuming...'
  end

  def extract_amazon_page_link_from_audible
    @review_page_state_object = JSON.parse(review_page.css('#cr-state-object').attr('data-state').value)
    state_object_signin_url = review_page_state_object['signinUrl']
    @amazon_path = if /openid.return_to/ =~ review_page_state_object['signinUrl']
                     open_id_connect_return_to_url = state_object_signin_url.split('?')[1].split('&').select { |val| val[0..15] == 'openid.return_to' }.first
                     URI.decode_www_form_component(open_id_connect_return_to_url.split('=')[1])
                        .gsub('product-reviews/', 'dp/')
                   elsif review_page_state_object['asin']
                     'http://' + URI.parse(state_object_signin_url).host + '/dp/' + review_page_state_object['asin']
                   end.gsub('audible', 'amazon')
  end

  def get_amazon_page
    @amazon_page = Nokogiri::HTML(agent.get(amazon_path).body)
    puts 'Pause after getting product page (to sneak past the amazon anti-scraping guards)'
    sleep(rand(1.0..3.0))
    puts 'Resuming...'
  end

  def output_data
    return construct_data_from_amazon.merge(finished_data) if finished

    construct_data_from_amazon
  end

  def construct_data_from_amazon
    {
      title: book_title,
      subtitle: book_subtitle,
      author: book_authors,
      date_started: '@TODO',
      format: {
        type: 'Audiobook',
        narrator: book_narrators,
        aisn: asin_numbers,
        publisher: book_publisher,
        version: book_version,
        listening_length: audio_book_runtime,
        year_released: audible_release_date.year,
        date_released: audible_release_date.strftime('%Y-%m-%d'),
        date_purchased: '@TODO'
      }
    }
  end

  def finished_data
    {
      date_finished: DateTime.now.strftime('%Y-%m-%d'),
      rating: {
        mine: 0
      }
    }
  end

  def audio_book_runtime
    amazon_page.css('#detailsListeningLength > td > span').text
  end

  def book_title
    audible_page.css('.bc-size-large').text
  end

  def book_subtitle
    audible_page.css('span.bc-size-medium').text
  end

  def book_authors
    audible_page.css('li.authorLabel > a').map(&:text)
  end

  def book_narrators
    audible_page.css('li.narratorLabel > a').map(&:text)
  end

  def book_aisns; end

  def book_publisher
    amazon_page.css('#detailspublisher > td > a').text
  end

  def book_version
    amazon_page.css('#detailsVersion > td > span').text
  end

  def audible_release_date
    Date.parse(amazon_page.css('#detailsReleaseDate > td > span').text)
  end

  def user_agent
    'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_11_6) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/71.0.3578.98 Safari/537.36'
  end

  def asin_numbers
    {
      product: product_asin,
      membership: membership_asin
    }.select { |_k, v| v }
  end

  def product_asin
    audible_page.css('.bc-trigger-sticky input[name=productAsin]').attr('value').value
  end

  def membership_asin
    audible_page.css('.bc-trigger-sticky input[name=membershipAsin]').attr('value').value
  end
end

url = ARGV[0]
finished = ARGV[1] == '--fin'
GetBookInfo.new(url, finished).call
