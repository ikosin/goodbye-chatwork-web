require 'sinatra/base'
require 'sinatra/reloader'
require 'action_view'
require 'goodbye_chatwork'
require 'csv'
require 'zip'
require 'fileutils'

class GoodbayChatWorkWeb < Sinatra::Base

  configure do
    enable :sessions

    helpers ActionView::Helpers::TextHelper
    helpers ERB::Util

    ENV["TZ"] = "Asia/Tokyo"
  end
  configure :development do
    set :bind, '0.0.0.0'
    register Sinatra::Reloader
    enable :logging
  end

  get '/' do
    erb :login
  end

  post '/rooms' do
    @mail_address = params[:mail_address]
    @password = params[:password]

    gcw = GoodbyeChatwork::Client.new(@mail_address, @password, verbose: true)
    gcw.login
    @rooms = gcw.room_list
    erb :rooms
  end

  post '/export' do
    @mail_address = params[:mail_address]
    @password = params[:password]
    @room_ids = params["room_ids"]

    t = Time.now().strftime("%Y%m%d_%H%M")
    work_dir = "/tmp/chatwork_log_#{t}"
    zipfile_name = "chatwork_log#{t}.zip"
    zipfile_path = "/tmp/#{zipfile_name}"
    FileUtils.mkdir_p work_dir

    gcw = GoodbyeChatwork::Client.new(@mail_address, @password, verbose: true)
    gcw.login
    list = gcw.room_list
    @rooms = []
    @room_ids.each do |room_id|
      @rooms << list.find { |i| i[0] == room_id.to_s }
    end

    @rooms.each do |room|
      room_id = room[0]
      room_name = room[1].gsub(/[[:cntrl:]\s\/\:]/, '')
      out = File.join(work_dir, "#{room_id}_#{room_name}.csv")
      file_dir = File.join(work_dir, "#{room_id}_files_#{room_name}")
      gcw.export_csv(room_id, out, { include_file: true, dir: file_dir })
    end

    zf = ZipFileGenerator.new(work_dir, zipfile_path)
    zf.write()
    p zipfile_path
    send_file(zipfile_path, :type => 'application/zip', :filename => zipfile_name)

    erb :rooms
  end

  run! if app_file == $0
end

# This is a simple example which uses rubyzip to
# recursively generate a zip file from the contents of
# a specified directory. The directory itself is not
# included in the archive, rather just its contents.
#
# Usage:
#   directory_to_zip = "/tmp/input"
#   output_file = "/tmp/out.zip"
#   zf = ZipFileGenerator.new(directory_to_zip, output_file)
#   zf.write()
class ZipFileGenerator
  # Initialize with the directory to zip and the location of the output archive.
  def initialize(input_dir, output_file)
    @input_dir = input_dir
    @output_file = output_file
  end

  # Zip the input directory.
  def write
    entries = Dir.entries(@input_dir) - %w(. ..)

    ::Zip::File.open(@output_file, ::Zip::File::CREATE) do |io|
      write_entries entries, '', io
    end
  end

  private

  # A helper method to make the recursion work.
  def write_entries(entries, path, io)
    entries.each do |e|
      zip_file_path = path == '' ? e : File.join(path, e)
      disk_file_path = File.join(@input_dir, zip_file_path)
      puts "Deflating #{disk_file_path}"

      if File.directory? disk_file_path
        recursively_deflate_directory(disk_file_path, io, zip_file_path)
      else
        put_into_archive(disk_file_path, io, zip_file_path)
      end
    end
  end

  def recursively_deflate_directory(disk_file_path, io, zip_file_path)
    io.mkdir zip_file_path
    subdir = Dir.entries(disk_file_path) - %w(. ..)
    write_entries subdir, zip_file_path, io
  end

  def put_into_archive(disk_file_path, io, zip_file_path)
    io.get_output_stream(zip_file_path) do |f|
      f.write(File.open(disk_file_path, 'rb').read)
    end
  end
end

