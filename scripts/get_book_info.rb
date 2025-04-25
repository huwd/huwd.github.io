require 'nokogiri'
require 'mechanize'
require 'json'
require 'pry'
require 'yaml'

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
    set_scaper_type
    extract_from_audible if @domain == 'audible'
    extract_from_amazon
    load_books_yml
    conditionally_write_to_file
  end

  private

  def load_books_yml
    @books = Dir.glob("_books/*.md").map do |file|
      frontmatter = File.read(file)[/\A---\s*\n(.*?)\n---/m, 1]
      YAML.safe_load(frontmatter || "", permitted_classes: [Time], aliases: true) || {}
    end
  end

  def conditionally_write_to_file
    if @books_yml.map { |book| "#{book['title']}#{book['format']}" }
                 .include?("#{output_data['title']}#{output_data['format']}")
      puts 'There appears to already be an entry for this book, manually copy paste:'
      puts ''
      puts [output_data.stringify_keys].to_yaml
    else
      File.open('_data/books.yml', 'w') do |file|
        file.write([output_data.stringify_keys, *@books_yml].to_yaml)
      end
    end
  end

  def set_scaper_type
    uri = URI.parse(@url)
    if uri.nil?
      puts 'URL is not processable by URI, please  check format'
      nil
    elsif uri.host.include?('amazon')
      @domain = 'amazon'
    elsif uri.host.include?('audible')
      @domain = 'audible'
    end
  end

  def create_scraping_agent
    @agent = Mechanize.new { |agent| agent.user_agent = user_agent }
  end

  def extract_from_amazon
    @amazon_path = @url if @domain == 'amazon'
    parse_amazon_page
  end

  def extract_from_audible
    @audible_path = @url.split('?')[0]
    parse_audible_page
    parse_amazon_review_page
    extract_amazon_page_link_from_audible
  end

  def parse_audible_page
    @audible_page = Nokogiri::HTML(agent.get(audible_path).body)
    puts 'Pause after getting audible page (to sneak past the amazon anti-scraping guards)'
    sleep(rand(1.0..3.0))
    puts 'Resuming...'
  end

  def parse_amazon_review_page
    review_path = "https://#{URI.parse(audible_path).host + audible_page.css('#adbl-amzn-portlet-reviews').attribute('src').value}"
    @review_page = Nokogiri::HTML(agent.get(review_path).body)
    puts 'Pause after getting review page (to sneak past the amazon anti-scraping guards)'
    sleep(rand(1.0..3.0))
    puts 'Resuming...'
  end

  def extract_amazon_page_link_from_audible
    @review_page_state_object = JSON.parse(review_page.css('#cr-state-object').attr('data-state').value)
    state_object_signin_url = review_page_state_object['signinUrl']
    @amazon_path = if /openid.return_to/ =~ review_page_state_object['signinUrl']
                     open_id_connect_return_to_url = state_object_signin_url.split('?')[1].split('&').select do |val|
                       val[0..15] == 'openid.return_to'
                     end.first
                     URI.decode_www_form_component(open_id_connect_return_to_url.split('=')[1])
                        .gsub('product-reviews/', 'dp/')
                   elsif review_page_state_object['asin']
                     "http://#{URI.parse(state_object_signin_url).host}/dp/#{review_page_state_object['asin']}"
                   end.gsub('audible', 'amazon')
  end

  def parse_amazon_page
    @amazon_page = Nokogiri::HTML(agent.get(amazon_path).body)
    puts 'Pause after getting product page (to sneak past the amazon anti-scraping guards)'
    sleep(rand(1.0..3.0))
    puts 'Resuming...'
  end

  def output_data
    {
      title: book_title,
      subtitle: book_subtitle,
      author: book_authors,
      **construct_format_data,
      date_started: Time.now.strftime('%Y-%m-%d'),
      **finished_data
    }.compact
  end

  def audiobook_format
    {
      type: book_format,
      narrator: audio_book_narrators,
      aisn: asin_numbers,
      publisher: audiobook_publisher,
      version: audiobook_version,
      listening_length: audio_book_runtime,
      year_released: audiobook_release_date.year,
      date_released: audiobook_release_date.strftime('%Y-%m-%d'),
      date_purchased: '@TODO'
    }
  end

  def text_book_format
    {
      type: book_format,
      **amazon_carousel,
      date_purchased: '@TODO'
    }
  end

  def construct_format_data
    {
      format: if @domain == 'audible'
                audiobook_format
              else
                text_book_format
              end
    }
  end

  def finished_data
    return {} unless finished

    {
      date_finished: DateTime.now.strftime('%Y-%m-%d'),
      rating: 0
    }
  end

  def audio_book_runtime
    amazon_page.css('#detailsListeningLength > td > span').text
  end

  def audio_book_narrators
    audible_page.css('li.narratorLabel > a').map(&:text)
  end

  def amazon_carousel
    carousel = amazon_page.css('ol.a-carousel')
    @amazon_carousel = carousel.css('.rpi-attribute-label>span')
                               .map(&:text)
                               .map { |label| label.downcase.gsub(' ', '_').gsub('-', '') }
                               .zip(
                                 carousel.css('.rpi-attribute-value>span').map(&:text)
                               ).to_h.symbol_keys
  end

  def book_format
    return 'Audiobook' if @domain == 'audible'

    amazon_page.css('#productSubtitle')
               .text
               .strip
               .split(" â\u0080\u0093 ")[0]
  end

  def page_title
    amazon_page.css('#productTitle').text.split(':')
  end

  def book_title
    return audible_page.css('.bc-size-large').text if @domain == 'audible'

    page_title.first.strip
  end

  def book_subtitle
    return audible_page.css('span.bc-size-medium').text if @domain == 'audible'

    return nil if page_title.length <= 1

    page_title.last.strip
  end

  def book_authors
    return audible_page.css('li.authorLabel > a').map(&:text) if @domain == 'audible'

    amazon_page.css('#bylineInfo > span.author a.a-link-normal').map(&:text)[3..-1]
  end

  def audiobook_publisher
    amazon_page.css('#detailspublisher > td > a').text
  end

  def audiobook_version
    amazon_page.css('#detailsVersion > td > span').text
  end

  def audiobook_release_date
    Date&.strptime(amazon_page.css('#detailsReleaseDate > td > span').text, '%d %B %Y')
  end

  def user_agent
    'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_11_6) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/71.0.3578.98 Safari/537.36'
  end

  def asin_numbers
    {
      product: product_asin,
      membership: membership_asin
    }
  end

  def product_asin
    audible_page.css('.bc-trigger-sticky input[name=productAsin]')&.attr('value')&.value
  end

  def membership_asin
    audible_page.css('.bc-trigger-sticky input[name=membershipAsin]')&.attr('value')&.value
  end
end

url = ARGV[0]
finished = ARGV[1] == '--fin'
GetBookInfo.new(url, finished).call
