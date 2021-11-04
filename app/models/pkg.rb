# == Schema Information
#
# Table name: pkgs
#
#  id             :integer          not null, primary key
#  app_id         :integer
#  name           :string
#  icon           :string
#  plat_name      :string
#  bundle_id      :string
#  version        :string
#  build          :string
#  created_at     :datetime         not null
#  updated_at     :datetime         not null
#  plat_id        :integer
#  file           :string
#  size           :integer          default(0)
#  uniq_key       :string
#  user_id        :integer
#  deleted_at     :datetime
#  file_nick_name :string
#

class Pkg < ApplicationRecord

  serialize :ext_info, Hash

  attr_accessor :app_icon
  include PlatAble

  belongs_to :app
  belongs_to :plat
  belongs_to :user

  validates_presence_of :user_id
  validates_presence_of :file, :file_nick_name

  mount_uploader :icon, IconUploader
  mount_uploader :file, PkgUploader

  enum plat_name: {
    ios: 'ios',
    android: 'android'
  }

  after_create :save_icon
  after_create :clean_tmp

  def initialize pars
    super pars
    parsing
  end

  def uniq?
    !self.class.where({plat_id:plat_id,self.uniq_key.to_sym => self[self.uniq_key.to_sym]}).exists?
  end

  def size_mb
   '%.1f' % (size / (1024*1024.0))
  end

  def parsing
    if file.path
      parser.parse
      self.name = parser.app_name
      self.app_icon = parser.app_icon
      self.version = parser.app_version
      self.build = parser.app_build
      self.size = parser.app_size
      self.bundle_id = parser.app_bundle_id
      self.plat_name = parser.plat
      self.uniq_key = parser.app_uniq_key
      self.ext_info = parser.ext_info
    end
  end

  def parser
    @parser ||= PkgAdapter.pkg_adapter(file.path)
  end

  def save_icon
    if app_icon&.end_with?(".png")
      self.icon.store!(File.new(app_icon))
      self.save
    end
  end

  def clean_tmp
    if File.exist?(parser.tmp_dir)
      FileUtils.rm_rf parser.tmp_dir
    end
  end

  def pkg_after_store
    begin
      shell = "#{Rails.root.join("config")}/pkg_after_create.sh"
      if File.exist?(shell)
        system("bash #{shell} '#{file.path}'")
      end
    rescue => e
      puts e
    end
  end

  def install_url
    if ios?
      "itms-services://?action=download-manifest&url=#{Current.request.base_url}#{Rails.application.routes.url_helpers.manifest_pkg_path(self)}.plist"    
    else
      download_url
    end
  end

  def download_url
    file_path = "#{self.file}"
    if Settings.pkg_cdn_host.present? && !File.exist?("#{Rails.root.join('public')}#{file_path}")
      return "#{Settings.pkg_cdn_host}#{file_path}"
    else
      return "#{Current.request.base_url}#{file_path}"
    end
  end

  def display_file_name
    File.basename(file.path,".*")
  end

  def to_render_json
    key_white_list = [:id,:app_id,:name,:file_nick_name,:features,:plat_name,:plat_id,:bundle_id,:version,:build,:size_mb,:uniq_key,:user_id,:ext_info,:install_url,:download_url,:created_at]
    json = {}
    key_white_list.each do |key|
      json[key] = self.send(key.to_s)
    end
    json[:icon_url] = "#{Current.request.base_url}#{icon.url}"
    json
  end

  
end
