require 'erb'
require File.expand_path(File.join(File.dirname(__FILE__), 'dependencies'))

class PardotProspectCreateV2
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
      'user_key' => user_key,
      'campaign_id' => @parameters['campaign_id']
    }

    params["first_name"] = @parameters['first_name'] if !@parameters['first_name'].empty?
    params["last_name"] = @parameters['last_name'] if !@parameters['last_name'].empty?
    params["company"] = @parameters['company'] if !@parameters['company'].empty?
    params["phone"] = @parameters['phone'] if !@parameters['phone'].empty?

    puts "Creating the new prospect" if @enable_debug_logging
    begin
      result = RestClient.get "https://pi.pardot.com/api/prospect/version/3/do/upsert/email/#{ERB::Util.url_encode(email_address)}", {:params => params}
    rescue RestClient::BadRequest => error
      raise StandardError, error.inspect
    end

    puts "Pardot Prospect Create response" if @enable_debug_logging
    puts result

    doc = REXML::Document.new(result)
    prospect_id = ""
    if doc.elements["rsp"].attributes["stat"] != "ok"
      raise StandardError, doc.elements["rsp"].elements["err"].text
    else
      REXML::XPath.match(doc, 'rsp/prospect/id').each do |node|
        prospect_id = node.text.to_s
      end
    end

    puts "Checking to see if Prospect needs to be reassigned" if @enable_debug_logging
    if (@parameters["assign_to"] != @info_values["email"]) and (@parameters["assign_to"] != "")
      unassign_params = {
        'api_key' => api_key,
        'user_key' => user_key,
        'email' => @info_values['email']
      }

      # Unassigning from the user who created it before reassigning it to the correct person
      puts "Unassigning Prospect from #{@info_values['email']}" if @enable_debug_logging
      begin
        result = RestClient.get "https://pi.pardot.com/api/prospect/version/3/do/unassign/email/#{ERB::Util.url_encode(email_address)}", {:params => unassign_params}
      rescue RestClient::BadRequest => error
        raise StandardError, error.inspect
      end

      puts "Unassign Prospect response:" if @enable_debug_logging
      puts result

      assign_params = {
        'api_key' => api_key,
        'user_key' => user_key,
        'user_email' => @parameters['assign_to']
      }

      # Assigning the prospect to the email contained in the parameters
      puts "Assigning Prospect to #{email_address}" if @enable_debug_logging
      begin
        result = RestClient.get "https://pi.pardot.com/api/prospect/version/3/do/assign/email/#{ERB::Util.url_encode(email_address)}", {:params => assign_params}
      rescue RestClient::BadRequest => error
        raise StandardError, error.inspect
      end

      puts "Assign Prospect response:" if @enable_debug_logging
      puts result

    end


    puts "Returning results" if @enable_debug_logging
    <<-RESULTS
    <results>
      <result name="id">#{prospect_id}</result>
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
