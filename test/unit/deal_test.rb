require File.dirname(__FILE__) + '/../test_helper'

class DealTest < Test::Unit::TestCase
#  fixtures :deals
  fixtures :accounts
  fixtures :users

  def test_create_simple
    user = User.find(1)
    assert user
    
    deal = Deal.new({:summary => "おにぎり", :amount => "105", :minus_account_id => "1", :plus_account_id => "2"})

    # 追加
    deal = Deal.create_or_update_simple(
      deal,
      user.id,
      Date.parse("2006/04/01"), nil)

    deal = Deal.find(1)
    assert deal
    assert_equal user.id, deal.user_id
    assert_equal "おにぎり", deal.summary
    assert_equal 4, deal.date.month
    assert_equal 2006, deal.date.year
    assert_equal 2, deal.account_entries.size
    assert_equal deal.account_entries[0].account_id, 1
    assert_equal deal.account_entries[0].amount, -105
    assert_equal deal.account_entries[0].deal_id, 1
    assert_equal deal.account_entries[1].account_id, 2
    assert_equal deal.account_entries[1].amount, 105
    assert_equal deal.account_entries[1].deal_id, 1
    assert_equal 1, deal.daily_seq

    # 追加
    deal2 = Deal.new({:summary => "おにぎり", :amount => "105", :minus_account_id => "1", :plus_account_id => "2"})
    deal2 = Deal.create_or_update_simple(
      deal2,
      user.id,
      Date.parse("2006/04/01"), nil)

    assert_equal 2, deal2.daily_seq
    
    #2の前に挿入
    deal3 = Deal.new({:summary => "おにぎり", :amount => "105", :minus_account_id => "1", :plus_account_id => "2"})
    deal3 = Deal.create_or_update_simple(
      deal3,
      user.id,
      Date.parse("2006/04/01"), deal2)
   
   assert_equal 2, deal3.daily_seq
   
   #dealがそのままでdeal2が3になることを確認
   deal = Deal.find(deal.id)
   assert_equal 1, deal.daily_seq
   
   deal2 = Deal.find(deal2.id)
   assert_equal 3, deal2.daily_seq
   
    #日付違いを追加したら新規になることを確認
    deal4 = Deal.new({:summary => "おにぎり", :amount => "105", :minus_account_id => "1", :plus_account_id => "2"})
    deal4 = Deal.create_or_update_simple(
      deal4,
      user.id,
      Date.parse("2006/04/02"), nil)
    assert_equal 1, deal4.daily_seq
    
    #日付違いによる挿入がうまくいくことを確認
    deal5 = Deal.new({:summary => "おにぎり", :amount => "105", :minus_account_id => "1", :plus_account_id => "2"})
    deal5 = Deal.create_or_update_simple(
      deal5,
      user.id,
      Date.parse("2006/04/02"), deal4)
    assert_equal 1, deal5.daily_seq
    deal4 = Deal.find(deal4.id)
    assert_equal 2, deal4.daily_seq
    
    #日付と挿入ポイントがあっていないと例外が発生することを確認
    begin
      dealx = Deal.new({:summary => "おにぎり", :amount => "105", :minus_account_id => "1", :plus_account_id => "2"})
      Deal.create_or_update_simple(
        dealx,
        user.id,
        Date.parse("2006/04/02"), deal)
      assert false
    rescue ArgumentError
      assert true
    end
  end
end
