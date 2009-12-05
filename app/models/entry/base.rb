# １口座への１記入を表す
class Entry::Base < ActiveRecord::Base
  set_table_name 'account_entries'
  unsavable
  
  belongs_to :account,
             :class_name => 'Account::Base',
             :foreign_key => 'account_id'

  # TODO: account.deals を使っているところのためにとりあえず
  belongs_to :deal,
             :class_name => 'Deal::Base',
             :foreign_key => 'deal_id'


  validates_presence_of :amount, :account_id
  before_update :store_old_amount
  before_save :copy_deal_attributes
  after_save :update_balance, :request_linking

  after_destroy :update_balance, :request_unlinking

  attr_accessor :balance_estimated, :unknown_amount, :account_to_be_connected, :another_entry_account, :flow_sum
  attr_accessor :skip_linking # 要請されて作る場合、リンクしにいくのは不要なので
  attr_reader :new_plus_link
  attr_protected :user_id, :deal_id, :date, :daily_seq, :settlement_id, :result_settlement_id

  attr_writer :skip_unlinking

  named_scope :confirmed, :conditions => {:confirmed => true}
  named_scope :date_from, Proc.new{|d| {:conditions => ["date >= ?", d]}} # TODO: 名前バッティングで from → date_from にした
  named_scope :before, Proc.new{|d| {:conditions => ["date < ?", d]}}
  named_scope :ordered, :order => "date, daily_seq"
  named_scope :of, Proc.new{|account_id| {:conditions => {:account_id => account_id}}}
  named_scope :after, Proc.new{|e| {:conditions => ["date > ? or (date = ? and daily_seq > ?)", e.date, e.date, e.daily_seq]} }


  # コンマ混じりの文字列でamountを代入できる
  def formatted_amount=(formatted_amount)
    self.amount = formatted_amount.class == String ? formatted_amount.gsub(/,/,'') : formatted_amount
  end
  # フィールドで利用できるよう用意するがこちらは,をつけない
  def formatted_amount
    self.amount
  end

  # コンマ混じりの文字列でbalanceを代入できる
  def formatted_balance=(formatted_balance)
    self.balance = formatted_balance.class == String ? formatted_balance.gsub(/,/,'') : formatted_balance
  end
  # フィールドで利用できるよう用意するがこちらは,をつけない
  def formatted_balance
    self.balance
  end

  def to_xml(options = {})
    options[:indent] ||= 4
    xml = options[:builder] ||= Builder::XmlMarkup.new(:indent => options[:indent])
    xml.instruct! unless options[:skip_instruct]
    xml_attributes = {:account => "account#{self.account_id}"}
    xml_attributes[:settlement] = "settlement#{self.settlement_id}" unless self.settlement_id.blank?
    xml_attributes[:result_settlement] = "settlement#{self.result_settlement_id}" unless self.result_settlement_id.blank?
    xml.entry(amount, xml_attributes)
  end

  def to_csv
    ["entry", self.deal_id, self.account_id, self.settlement_id, self.result_settlement_id, amount].join(',')
  end

  # 精算が紐付いているかどうかを返す。外部キーを見るだけで実際に検索は行わない。
  def settlement_attached?
    not (self.settlement_id.blank? && self.result_settlement_id.blank?)
  end

  # 相手勘定名を返す
  def mate_account_name
    raise AssociatedObjectMissingError, "no deal" unless deal
    deal.mate_account_name_for(account_id)
  end

  # リンクされたaccount_entry を返す
  # TODO: 廃止する
  def linked_account_entry
    linked_ex_entry_id ? Entry::Base.find_by_id(linked_ex_entry_id) : nil
  end

  # 所属するDealが確認済ならリンクをクリアし、未確認なら削除する
  def unlink
#    p "unlink"
    raise AssociatedObjectMissingError, "my_entry.deal is not found" unless deal
    if !deal.confirmed
      # TODO: このentryについては削除したときに相手をunlink仕返さないことを指定
      # オブジェクトとしては別物なので困ってしまう
      deal.entries.detect{|e| e.id == self.id}.skip_unlinking = true
      deal.destroy
    else
      Entry::Base.update_all("linked_ex_entry_id = null, linked_ex_deal_id = null, linked_user_id = null", "id = #{self.id}")
      self.linked_ex_entry_id = nil
      self.linked_ex_deal_id = nil
      self.linked_user_id = nil
    end
  end

  def after_confirmed
    update_balance
  end

  # コールバックのほか、精算提出などで単独でも呼ばれる
  def request_linking
    return if !changed? # 内容が変更されていななら何もしない
    return if skip_linking
#    p "request_linking of #{self.id}"
    return if !account || !account.linked_account || !self.deal

    # TODO: 残高は連携せず、移動だけを連携する。いずれ残高記入も連携したいがそれにはAccountEntryのクラスわけが必要か。
    self.linked_ex_entry_id, self.linked_ex_deal_id = account.linked_account.update_link_to(self.id, self.deal_id, self.user_id, self.amount, self.deal.summary, self.date)
    self.linked_user_id = account.linked_account.user_id

    update_links_without_callback
  end

  def update_links_without_callback
    raise "new_record!" if new_record?
    Entry::Base.update_all("linked_ex_entry_id = #{linked_ex_entry_id}, linked_ex_deal_id = #{linked_ex_deal_id}, linked_user_id = #{linked_user_id}", ["id = ?", self.id])
  end


  private


  def store_old_amount
    @old_amount = self.class.find(self.id).amount
  end

  def copy_deal_attributes
    # 基本的にDealからコピーするがDealがないケースも許容する
    if deal && deal.kind_of?(Deal::General) # TODO: 残高では常に作り直す上にbefore系コールバックでbuildするため、これだと変更処理がうまくいかない
      self.user_id = deal.user_id
      self.date = deal.date
      self.daily_seq = deal.daily_seq
    end
    raise "no user_id" unless self.user_id
    raise "no date" unless self.date
    raise "no daily_seq" unless self.daily_seq
  end

  # リンクしている口座があれば、連携記入の作成/更新を相手口座に依頼する

  def request_unlinking
    return if @skip_unlinking
        # TODO: linked_account_idもほしい　関連づけかえられてたら困る
    account.linked_account.unlink_to(self.id, self.user_id) if account && account.linked_account
  end

  def contents_updated?
    stored = Entry::Base.find(self.id)

    # 金額/残高が変更されていたら中身が変わったとみなす
    stored.amount.to_i != self.amount.to_i || stored.balance.to_i != self.balance.to_i
  end

  def assert_no_settlement
    raise "精算データに紐づいているため削除できません。さきに精算データを削除してください。" if self.settlement || self.result_settlement
  end

  # 直後の残高記入のamountを再計算する
  def update_balance
    next_balance_entry = Entry::Balance.of(account_id).after(self).ordered.first(:include => :deal)
#    next_balance_entry = Entry::Base.find(:first,
#    :joins => "inner join deals on account_entries.deal_id = deals.id",
#    :conditions => ["deals.type = 'Balance' and account_id = ? and (deals.date > ? or (deals.date = ? and deals.daily_seq > ?))", account_id, date, date, daily_seq],
#    :order => "deals.date, deals.daily_seq",
#    :include => :deal)
#    p "update balance at #{self.inspect}"
#    p "next_balance_entry = #{next_balance_entry.inspect}"
    return unless next_balance_entry
    next_balance_entry.deal.update_amount # TODO: 効率
  end

end
