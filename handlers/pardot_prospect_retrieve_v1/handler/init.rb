require 'erb'
require File.expand_path(File.join(File.dirname(__FILE__), 'dependencies'))

class PardotProspectRetrieveV1
  def initialize(input)
    # Set the input document attribute
    @input_document = REXML::Document.new(input)
    
    # Store the info values in a Hash of info names to values.
    @info_values = {}
    REXML::XPath.each(@input_document,"/handler/infos/info") { |item|
      @info_values[item.attributes['name']] = item.text  
    }
    
    # Retrieve all of the handler parameters and store them in a hash attribute
    # named @parameters.
    @parameters = {}
    REXML::XPath.match(@input_document, 'handler/parameters/parameter').each do |node|
      @parameters[node.attribute('name').value] = node.text.to_s
    end

    @enable_debug_logging = @info_values['enable_debug_logging'] == 'Yes'
  end
  
  def execute() 
    api_key = get_api_key(@info_values['email'], @info_values['password'], @info_values['api_user_key'])
    user_key = @info_values['api_user_key']

    # Get the email address and ensure there are no leading/trailing whitespace
    email_address = (@parameters['email'] || "").strip

    # Initializing the parameter list with 
    params = {
      'api_key' => api_key,
      'user_key' => user_key
    }

    puts "Retrieving the prospect cooresponding to #{email_address}" if @enable_debug_logging
    begin
      result = RestClient.get "https://pi.pardot.com/api/prospect/version/3/do/read/email/#{ERB::Util.url_encode(email_address)}", {:params => params}
    rescue RestClient::BadRequest => error
      raise StandardError, error.inspect
    end

    puts "Pardot Prospect Retrieve response" if @enable_debug_logging
    puts result

    return_hash = {}
    doc = REXML::Document.new(result)
    REXML::XPath.match(doc, 'rsp/prospect').each do |node|
      # The strings in the following list are the names of the nodes
      # that are being returned by the handler
      ["id","first_name","last_name","campaign_id","email","phone"].each do |field|
        return_hash[field] = node.elements[field].text
      end

      # also return assigned_to email if it exists, which has more 
      # nested xml than the other fields
      if node.elements["assigned_to"] != nil
        return_hash["assigned_to"] = node.elements["assigned_to"].elements["user"].elements["email"].text
      else
        return_hash["assigned_to"] = ""
      end
    end

    puts "Returning results" if @enable_debug_logging
    <<-RESULTS
    <results>
      <result name="id">#{escape(return_hash["id"])}</result>
      <result name="first_name">#{escape(return_hash["first_name"])}</result>
      <result name="last_name">#{escape(return_hash["last_name"])}</result>
      <result name="campaign_id">#{escape(return_hash["campaign_id"])}</result>
      <result name="email">#{escape(return_hash["email"])}</result>
      <result name="phone">#{escape(return_hash["phone"])}</result>
      <result name="assigned_to">#{escape(return_hash["assigned_to"])}</result>
    </results>
    RESULTS
  end

  def get_api_key(email, password, api_user_key)
    puts "Getting a current API key" if @enable_debug_logging
    params = {
      'email' => email,
      'password' => password,
      'user_key' => api_user_key
    }

    result = RestClient.post("https://pi.pardot.com/api/login/version/3",params)
    doc = REXML::Document.new(result)

    puts result

    api_key = ""
    REXML::XPath.match(doc, 'rsp/api_key').each do |node|
      api_key = node.text.to_s
    end

    return api_key
  end

  
  # This is a template method that is used to escape results values (returned in
  # execute) that would cause the XML to be invalid.  This method is not
  # necessary if values do not contain character that have special meaning in
  # XML (&, ", <, and >), however it is a good practice to use it for all return
  # variable results in case the value could include one of those characters in
  # the future.  This method can be copied and reused between handlers.
  def escape(string)
    # Globally replace characters based on the ESCAPE_CHARACTERS constant
    string.to_s.gsub(/[&"><]/) { |special| ESCAPE_CHARACTERS[special] } if string
  end
  # This is a ruby constant that is used by the escape method
  ESCAPE_CHARACTERS = {'&'=>'&amp;', '>'=>'&gt;', '<'=>'&lt;', '"' => '&quot;'}
end
