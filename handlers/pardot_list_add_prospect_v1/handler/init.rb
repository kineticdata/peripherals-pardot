require 'erb'
require File.expand_path(File.join(File.dirname(__FILE__), 'dependencies'))

class PardotListAddProspectV1
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

    list_name = "list_" + @parameters["list_id"]
    params[list_name] = "1"
    
    if @enable_debug_logging
      puts "Updating the prospect to subscribe it to the list with the API list name  of #{@parameters['list_name']}"
      puts "---------------------"
      puts "PARAMS: #{params}"
      puts "---------------------"
    end

    begin
      result = RestClient.get "https://pi.pardot.com/api/prospect/version/3/do/update/email/#{ERB::Util.url_encode(email_address)}", {:params => params}
    rescue RestClient::BadRequest => error
      raise StandardError, error.inspect
    end
    puts result if @enable_debug_logging

    doc = REXML::Document.new(result)

    # Check if the prospect has been added to the list. If it has not been,
    # throw an error
    prospect_object = doc.elements["rsp"].elements["prospect"]
    if prospect_object.elements["lists"] == nil
      raise StandardError, "Unknown Error: The prospect #{email_address} was not added to the list with the id of #{@parameters['list_id']}"
    else
      list_added = false
      REXML::XPath.match(doc, 'rsp/prospect/lists/list_subscription/list/id').each do |list_id|
        if list_id.text == @parameters['list_id']
          list_added = true
          break
        end
      end

      if list_added == false
        raise StandardError, "Unknown Error: The prospect #{email_address} was not added to the list with the id of #{@parameters['list_id']}"
      end
    end

    return "<results/>"
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
