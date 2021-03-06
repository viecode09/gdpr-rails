module Encryptable

  def redis_connection
    redis = Redis.new
    Redis::Namespace.new(:encrypt, :redis => redis)
  end

  def encryption_key
    namespaced_redis = self.redis_connection
    if self.class.name == 'User'
      if self.id
        key = self.id.to_s
        @encryption_key = namespaced_redis.get(key)
        return @encryption_key
      else #for new records
        @encryption_key ||= self.create_encryption_key
        return @encryption_key
      end
    end
    if (defined?(self.user_id))
      key = self.user_id.to_s
      raise ArgumentError('Invalid user_id') unless key.length > 0
      @encryption_key = namespaced_redis.get(key)
      return @encryption_key
    else
      raise 'You need to override an encryption_key method - no
        direct connection to user_id'
    end
  end

  def create_encryption_key #we might only need this in our User model but it's still part of our encryptable library
    Rails.application.secrets.partial_encryption_key + SecureRandom.random_bytes(28)
    #we take 4 bytes of our encryption_key from application secrets file wuth remaining 28 to be stored inside Redis
  end

  #attr_encrypted requires encrypted_fieldname_iv to exist in the database. This method will automatically populate all of them
  def populate_iv_fields
    fields = self.attributes.reject {|attr| !(attr.include?('iv') && attr.include?('encrypted')) }.keys
    fields.each do |field|
      unless self.public_send(field) #just in case so it's impossible to overwrite our iv
        iv = SecureRandom.random_bytes(12)
        self.public_send(field+'=', iv)
      end
    end
  end
  #this saves our encryption key in Redis so it's persistent
  def save_encryption_key
    namespaced_redis = self.redis_connection
    if defined?(self.user_id)
      key = self.user_id.to_s
    else
      key = self.id.to_s
    end
    #just to stay on safe side
    raise 'Encryption key already exists' if namespaced_redis.get(key)
    namespaced_redis.set(key, @encryption_key)
  end

  #what do return in attribute field when there's no key
  def value_when_no_key
    '[deleted]'
  end

  #we need to override attr_encrypted method so rather than throwing an exception
  #it will return a correct value when no key exists
  #you can also consider overriding encrypt in a similar fashion (although for me it makes sense that no key = you cant edit whats inside)
  def decrypt(attribute, encrypted_value)
    begin
      encrypted_attributes[attribute.to_sym][:operation] = :decrypting
      encrypted_attributes[attribute.to_sym][:value_present] = self.class.not_empty?(encrypted_value)
      self.class.decrypt(attribute, encrypted_value, evaluated_attr_encrypted_options_for(attribute))
    rescue ArgumentError #must specify a key
      return self.value_when_no_key
    end
  end

end
