#!/usr/bin/env python

import time
import sys
from selenium import webdriver
from selenium.webdriver.support.ui import Select

def grab_data( keyword ):
    driver = webdriver.Chrome()
    baseurl="http://dmz9.moea.gov.tw/gmweb/advance/AdvanceQuery.aspx"
    driver.get(baseurl)

    select1 = Select(driver.find_element_by_id('ContentPlaceHolder1_ddlPeriod'))
    select1.select_by_visible_text("年")
    select2 = Select(driver.find_element_by_id('ContentPlaceHolder1_ddlDateKind'))
    select2.select_by_visible_text("西元")
    for i in range(0,5):
      #print(i)
      try:
        select3 = Select(driver.find_element_by_id('ContentPlaceHolder1_ddlDateBeg'))
        select3.select_by_visible_text("1981")
        break;
      except:
        time.sleep(3)
        continue;

    driver.find_elements_by_link_text('工廠校正')[0].click()
    driver.find_elements_by_link_text(keyword)[0].click()
    driver.find_elements_by_link_text('按第9次行業標準分(含細行業別)')[0].click()

    driver.find_elements_by_xpath("//*[contains(text(),'全選')]/parent::*/input[@type='checkbox']")[0].click()
    driver.find_elements_by_xpath("//*[contains(text(),'全選')]/parent::*/input[@type='checkbox']")[1].click()
    #for itm in driver.find_elements_by_xpath('//input[@type="checkbox"]'):
    #    if itm.is_selected():
    #        continue
    #    else:
    #        itm.click()

    driver.find_element_by_id('ContentPlaceHolder1_btnQuery').click()

    from io import BytesIO
    from lxml import html
    tree = html.parse(BytesIO(str.encode(driver.page_source)))
    [bad.getparent().remove(bad) for bad in tree.xpath("//td[@class='footnote']")]

    from lxml import etree
    import pandas
    dfs = pandas.read_html(etree.tostring(tree))[8]

    driver.quit()

    year_idx = {}

    for row_idx in range( 1, dfs[0].keys().__len__() ):
        #print(dfs[0][row_idx])
        year_idx[row_idx] = dfs[0][row_idx]

    for col_idx in range( 1, dfs[1:2].keys().__len__()-1 ):
        rows = dfs[col_idx]
        for idx in range( 2, rows.__len__()-1 ):
            prefix = "%04d" % (col_idx)
            title = rows[1]
            year = year_idx[idx].replace("年","")
            val = rows[idx]
            if val == "…":
                continue

            sys.stdout.write( "%s %s %s %s\n" % (val, year, prefix + "_"+ title, keyword) )

grab_data('年底從業員工人數')
grab_data('營運中工廠家數')
