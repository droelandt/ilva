require "net/http"
require 'nokogiri'
require 'google/apis/calendar_v3'
require 'googleauth'
require 'googleauth/stores/file_token_store'
require 'trollop'
require 'fileutils'

opts = Trollop::options do
  banner "Maakt voor ilva-afvalophalingen Google Calendar events aan."
  opt :streetnis, "ID van straat", type: :integer
  opt :nummer, "Straatnummer", type: :integer                
  opt :color, "ID van Google Calendar kleur", :default => 11   
end
year = Time.now.year.to_s
events = []
(1..12).each do |month|
  month = month.to_s
  source = Net::HTTP.get('ilva.be',"/afvalinzameling/kalender/detail.phtml?streetnis=#{opts[:streetnis].to_s}&number=#{opts[:nummer].to_s}&year=#{year}&month=#{month}")
  page = Nokogiri::HTML(source) 
  elements = page.xpath("//*[@background]")
  elements.select{|e| /\d/.match(e.attribute('background'))}.each do |td|
    if td.css("a").count > 0
    	day = td.attribute('background').text.gsub(/[^0-9]/, '')
      current = []
      td.css("a").each do |i|
        soort = i.css("img").attribute("alt")
        if !["Grofhuisvuil", "Snoeihout"].include?(soort.value)
          current.push(soort)
        end
      end
      events.push(["#{year}-#{month}-#{day}", current.join("\n")])
    end
  end
end
OOB_URI = 'urn:ietf:wg:oauth:2.0:oob'
APPLICATION_NAME = 'ilva to google calendar parser'
CLIENT_SECRETS_PATH = 'client_secret.json'
CREDENTIALS_PATH = File.join(Dir.home, '.credentials',
                             "calendar-ruby-quickstart.yaml")
SCOPE = Google::Apis::CalendarV3::AUTH_CALENDAR

##
# Ensure valid credentials, either by restoring from the saved credentials
# files or intitiating an OAuth2 authorization. If authorization is required,
# the user's default browser will be launched to approve the request.
#
# @return [Google::Auth::UserRefreshCredentials] OAuth2 credentials
def authorize
  FileUtils.mkdir_p(File.dirname(CREDENTIALS_PATH))

  client_id = Google::Auth::ClientId.from_file(CLIENT_SECRETS_PATH)
  token_store = Google::Auth::Stores::FileTokenStore.new(file: CREDENTIALS_PATH)
  authorizer = Google::Auth::UserAuthorizer.new(
    client_id, SCOPE, token_store)
  user_id = 'default'
  credentials = authorizer.get_credentials(user_id)
  if credentials.nil?
    url = authorizer.get_authorization_url(
      base_url: OOB_URI)
    puts "Open the following URL in the browser and enter the " +
         "resulting code after authorization"
    puts url
    code = gets
    credentials = authorizer.get_and_store_credentials_from_code(
      user_id: user_id, code: code, base_url: OOB_URI)
  end
  credentials
end

# Initialize the API
service = Google::Apis::CalendarV3::CalendarService.new
service.client_options.application_name = APPLICATION_NAME
service.authorization = authorize
events.each do |e|
  event = Google::Apis::CalendarV3::Event.new({
    "summary": e[1],
    "start": {
      "date_time":"#{e[0]}T08:00:00",
      "time_zone":'Europe/Brussels',
    },
    "end": {
      "date_time":"#{e[0]}T09:00:00",
      "time_zone":'Europe/Brussels',
    },
    "reminders": {
        "use_default": 'false'
    },  
    "color_id": opts[:color].to_s
  })
  result = service.insert_event('primary', event)
  puts "Event created: #{result.html_link}"
end
