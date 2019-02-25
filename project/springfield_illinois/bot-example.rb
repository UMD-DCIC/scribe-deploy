
require 'open-uri'
require 'json'
require 'cgi'

city = "Springfield"
# url = "https://transcribe.ischool.umd.edu"
url = "http://192.168.33.40:3000"

# Useful extension to Hash to create query strings:
class Hash
  def to_params
    params = ''
    stack = []

    each do |k, v|
      if v.is_a?(Hash)
        stack << [k,v]
      elsif v.is_a?(Array)
        stack << [k,Hash.from_array(v)]
      else
        params << "#{k}=#{v}&"
      end
    end

    stack.each do |parent, hash|
      hash.each do |k, v|
        if v.is_a?(Hash)
          stack << ["#{parent}[#{k}]", v]
        else
          params << "#{parent}[#{k}]=#{v}&"
        end
      end
    end

    params.chop! 
    params
  end

  def self.from_array(array = [])
    h = Hash.new
    array.size.times do |t|
      h[t] = array[t]
    end
    h
  end

end

# Example Scribe bot class:
class ScribeBot

  def initialize(scribe_endpoint)
    @classifications_endpoint = scribe_endpoint
  end

  # Post classification for a known subject_id
  def classify_subject_by_id(subject_id, workflow_name, task_key, data)
    params = {
      workflow: {
        name: workflow_name
      },
      classifications: {
        annotation: data,
        task_key: task_key,
        subject_id: subject_id
      }
    }

    submit_classification params
  end

  # Post classification for subject specified by URL:
  def classify_subject_by_url(subject_url, workflow_name, task_key, data)
    params = {
      subject: { 
        location: { 
          standard: CGI::escape(subject_url)
        }
      },
      workflow: {
        name: workflow_name
      },
      classifications: {
        annotation: data,
        task_key: task_key
      }
    }

    submit_classification params
  end

  # Posts params as-is to classifications endpoint:
  def submit_classification(params)

    require 'uri'
    require "net/http"

    uri = URI(@classifications_endpoint)
    puts uri
    puts uri.path
    req = Net::HTTP::Post.new(uri, {'BOT_AUTH' => ENV['SCRIBE_BOT_TOKEN']})
    puts req

    req.body = params.to_params     
    http = Net::HTTP.new(uri.host, uri.port)
    http.set_debug_output($stdout)
    # http.use_ssl = true

    response = http.start {|http| http.request(req) }
    
    begin
      JSON.parse response.body

    rescue
      nil
    end
  end
end

# This simple script demonstrates use of the Scribe Classifications endpoint to generate data
#
# Useage: 
#   ruby bot-example.rb [-scribe-endpoint="http://localhost:3000"]
#

options = Hash[ ARGV.join(' ').scan(/--?([^=\s]+)(?:=(\S+))?/) ]
options["scribe-endpoint"] = url + "/classifications" if ! options["scribe-endpoint"]

args = ARGV.select { |a| ! a.match /^-/ }

bot = ScribeBot.new options["scribe-endpoint"]

# The following generates generates two classfiications: One mark classification 
# and one transcription classification (applied to the subject generated by the
# mark classification).

# Specify subject by standard URL (since this is a bot classification, it will be created automatically if it doesn't exist)
# image_uri = "https://s3.amazonaws.com/scribe.nypl.org/emigrant-s4/full/619aed10-23fd-0133-16de-58d385a7bbd0.right-bottom.jpg"

require 'csv'

paths = ['subjects/group_' + city + '.csv']

paths.each do |path|
  CSV.foreach(path) do |row|
    next if row[2]== "file_path"
    puts row[2]
    image_uri = row[2]

    CSV.foreach('marks.csv') do |r|
      classification = bot.classify_subject_by_url( image_uri, "mark", "mark_primary", {
        belongsToUser: "true",
        toolName: "rectangleTool", 
        userCreated: "true", 
        color: "red", 
        isTranscribable: "true", 
        status: "mark", 
        isUncommitted: "true",        
        x: r[0], 
        y: r[1], 
        width: r[2], 
        height: r[3],
        subToolIndex: r[4],     # Must specify subToolIndex (integer index into the tools array configured for workflow task)
        _key: r[5]
      })['classification']
      # puts classification
      # classification = classification['classification']

      # Response should contain a classification with a nested child_subject:
      # puts "Created classification: #{classification.to_json}"
      break      
    end     

    classification = bot.classify_subject_by_url( image_uri, "mark", "completion_assessment_task", {
      value: "complete_subject"
    })['classification']
    break
  end
  
end

# Must manually specify workflow name ('mark'), and task_key ('mark_primary')


# # Assuming above was successful, use the returned, generated subject_id to create next classification:
# mark_id = classification['child_subject']['id']
# # Subjects generated in Mark tend to have `type`s that correspond to Transcribe task keys:
# transcribe_task_key = classification['child_subject']['type']
# # Create transcription classification:
# classification = bot.classify_subject_by_id( mark_id, "transcribe", transcribe_task_key, { value: 'foo' })

# # Response should contain a classification with a nested verify subject (or orphaned subject if there is no Verify workflow)
# puts "Created transcription classification: #{classification.to_json}"
