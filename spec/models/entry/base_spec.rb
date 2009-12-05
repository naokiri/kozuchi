require File.expand_path(File.dirname(__FILE__) + '/../../spec_helper')

describe Entry::Base do
  fixtures :accounts, :users, :account_links, :friend_permissions, :friend_requests
  set_fixture_class  :accounts => Account::Base

  before do
    @cache = accounts(:account_enrty_test_cache)
    @food = accounts(:account_entry_test_food)

    @user_hanako = users(:account_entry_test_user_hanako)
    @user_taro = users(:account_entry_test_user_taro)
    @hanako_in_taro = accounts(:account_entry_test_hanako_in_taro)
    @cache_in_taro = accounts(:account_entry_test_cache_in_taro)
    @taro_in_hanako = accounts(:account_entry_test_taro_in_hanako)
    @cache_in_hanako = accounts(:account_entry_test_cache_in_hanako)

    raise "前提エラー：@user_hanakoと@user_taroが友達ではありません" unless @user_hanako.friend?(@user_taro)
    raise "前提エラー：@hanako_in_taroに記入したものが@taro_in_hanakoに記入される設定になっていません" unless @hanako_in_taro.linked_account == @taro_in_hanako
  end

  describe "formatted_amount=" do
    it "コンマ入りの数字が正規化されて代入される" do
      new_account_entry(:formatted_amount => "10,000").amount.should == 10000
    end
  end
  describe "formatted_amount" do
    it "コンマ入りで入れてもゲッタでは,がつかない" do
      new_account_entry(:formatted_amount => "10,000").formatted_amount.should == 10000
    end
  end
  describe "formatted_balance=" do
    it "コンマ入りの数字が正規化されて代入される" do
      new_account_entry(:formatted_balance => "10,500").balance.should == 10500
    end
  end
  describe "formatted_balance" do
    it "コンマ入りで入れてもゲッタでは,がつかない" do
      new_account_entry(:formatted_balance => "10,500").formatted_balance.should == 10500
    end
  end


  describe "attributes=" do
    it "user_idは一括指定できない" do
      Entry::General.new(:user_id => 3).user_id.should_not == 3
    end
    it "deal_idは一括指定できない" do
      Entry::General.new(:deal_id => 7).deal_id.should_not == 7
    end
    it "account_idは一括指定できる" do
      Entry::General.new(:account_id => 5).account_id.should == 5
    end
    it "dateは一括指定できない" do
      Entry::General.new(:date => Date.today).date.should be_nil
    end
    it "daily_seqは一括指定できない" do
      Entry::General.new(:daily_seq => 3).daily_seq.should be_nil
    end
    it "settlement_idは一括指定できない" do
      Entry::General.new(:settlement_id => 10).settlement_id.should be_nil
    end
    it "result_settlement_idは一括指定できない" do
      Entry::General.new(:result_settlement_id => 10).result_settlement_id.should be_nil
    end
    # TODO: linked_系
  end

  describe "validate" do
    it "amountが指定されていないと検証エラー" do
      new_account_entry(:amount => nil).valid?.should be_false
    end
    it "account_idが指定されていないと検証エラー" do
      new_account_entry(:account_id => nil).valid?.should be_false
    end
  end

  describe "create" do
    it "account_id, amount, date, daily_seq, user_id があれば、deal_id の値によらず成功する" do
      e = Entry::General.new(:amount => 400, :account_id => @cache.id)
      e.date = Date.today
      e.daily_seq = 1
      e.user_id = 1
      e.save.should be_true
    end
    it "user_idがないと例外" do
      lambda{new_account_entry({}, :user_id => nil).save}.should raise_error(RuntimeError)
    end
    it "dateがないと例外" do
      lambda{new_account_entry({}, :date => nil).save}.should raise_error(RuntimeError)
    end
    it "daily_seqがないと例外" do
      lambda{new_account_entry({}, :daily_seq => nil).save}.should raise_error(RuntimeError)
    end
  end


  describe "destroy" do
    it "精算が紐付いていなければ消せる" do
      e = new_account_entry
      e.save!
      lambda{e.destroy}.should_not raise_error
    end
  end

  describe "settlement_attached?" do
    before do
      @entry = new_account_entry
    end
    it "settlement_id も result_settlement_idもないとき falseとなる" do
      @entry.save!
      @entry.settlement_attached?.should be_false
    end
    it "settlement_id があれば true になる" do
      @entry.settlement_id = 130 # 適当
      @entry.save!
      @entry.settlement_attached?.should be_true
    end
    it "result_settlement_id があれば true になる" do
      @entry.result_settlement_id = 130 # 適当
      @entry.save!
      @entry.settlement_attached?.should be_true
    end
  end

  describe "mate_account_name" do
    it "紐付いたdealがなければAssociatedObjectMissingErrorが発生する" do
      @entry = new_account_entry
      @entry.save!
      lambda{@entry.mate_account_name}.should raise_error(AssociatedObjectMissingError)
    end

    it "相手勘定が１つなら、相手勘定の名前が返される" do
      deal = new_deal(3, 3, @cache, @food, 180)
      deal.save!
#        deal = Deal::General.new(:summary => "買い物", :date => Date.today)
#        deal.entries.build(:amount => 180, :account_id => @food.id)
#        deal.entries.build(:amount => -180, :account_id => @cache.id)
#        deal.save!
      cache_entry = deal.entries.detect{|e| e.account_id == @cache.id}
      cache_entry.mate_account_name.should == @food.name
    end
  end

  describe "unlink" do
    before do
#      @deal = Deal::General.new(:summary => "test", :date => Date.today)
#      @deal.user_id = users(:account_entry_test_user_taro)
#      @deal.entries.build(
#        :account_id => @cache_in_taro.id,
#        :amount => -200
#        )
#      @deal.entries.build(
#        :account_id => @hanako_in_taro.id,
#        :amount => 200
#        )
#      @entry.save!

      @entry = Entry::General.new(:account_id => @hanako_in_taro.id, :amount => -200)
      @entry.daily_seq = 1
      @entry.date = Date.today
      @entry.linked_ex_entry_id = 18 # 適当
      @entry.user_id = Fixtures.identify(:taro)
    end
    it "linked_ex_entry_idを指定した新規登録なら連携記入がされないこと" do
      @entry.save!
      Entry::Base.find_by_linked_ex_entry_id(@entry.id).should be_nil
    end
    
  end


  # ----- Utilities -----
  def new_account_entry(attributes = {}, manual_attributes = {})
      e = Entry::General.new({:amount => 2980, :account_id => @cache.id}.merge(attributes))
      manual_attributes = {:date => Date.today, :daily_seq => 1, :user_id => 1}.merge(manual_attributes)
      manual_attributes.keys.each do |key|
        e.send("#{key}=", manual_attributes[key])
      end
      e
  end
  
  # TODO: dealの作り方をなおすまでとりあえず
  def new_deal(month, day, from, to, amount, year = 2008)
    d = Deal::General.new(:summary => "#{month}/#{day}の買い物", :amount => amount, :minus_account_id => from.id, :plus_account_id => to.id, :date => Date.new(year, month, day))
    d.user_id = to.user_id
    d
  end

end
