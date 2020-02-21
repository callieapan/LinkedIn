import pandas as pd
import numpy as np

def hasBachDeg(row, degwlist, mbawlist):
    if (any(degw in row['major']  for degw in degwlist)) and not (any (mw in row ['major'] for mw in mbawlist)):
        return True
    else:
        return False
    
def hasMasDeg(row, degwlist):
    if any(degw in row['major'] for degw in degwlist):
        return True
    else:
        return False
    
def findBachStart(group_df):
    '''
    function returns the most likely (min) year when the start year of earliest bachelor degree for each user 
    @param:
        group_df = eduDf[eduDf['hasbach']].groupby('user_id')
        this is the education table that has all rows with bachelor degree grouped by user_id
    @return 
        result = start year of the first bachelor degree 
    '''
    #some of the rows has one of the start or end y
    group_df1 = group_df.sort_values(by=['startyear'])
    group_df2 = group_df.sort_values(by=['endyear'])
    
    r1 = group_df1.iloc[0]['startyear']
    r2 = group_df1.iloc[0]['endyear'] - 4 #assume bachelor degrees take 4 years
    return min(r1, r2)
    
    


def getfirstjob(groupdf):
    
    '''
    function returns a Series that contains start year of the first job, min max seniority, for each user
    @param: groupdf = senposDf.groupby('user_id') 
    @return: for each user_id, return the year of the first job that person had, title, and seniority, Nan if none
    '''
    
    yr1= 3000 #impossible number
    if groupdf['startdate'].isnull().all(): #all of the ones is null
        yr1 = np.nan
    else:
        
        yr1 = groupdf['startdate'].fillna('3000').str[:4].astype(int).min()
    sen0 = groupdf['seniority'].min()
    senM = groupdf['seniority'].max()
    result = pd.Series({'first_job_year': yr1,  #'first_job_title': title1, 'first_job_sen': sen1,
                        'min_sen': sen0, 'max_sen': senM
                       })
    return result


def findSenSimId(comDf_pred_sen, comDf_label_sen):
    '''
    finds the labeled user that is 'closest' to the prediction user in min and max seniority
    @param:
        combDf_pred_sen = df with prediction users and their seniority and the index of pred_user_ids
        combDf_label_sen = df with labeled users and their seniority and the index of label_user_ids
    @return : id_list_test - a list that is the index of the label_user_ids in comDf_label_sen for each user in pred
    '''
    
    pred_sen_M = comDf_pred_sen[['min_sen', 'max_sen']].to_numpy()
    label_sen_M = comDf_label_sen[['min_sen', 'max_sen']].to_numpy()
    repdim = comDf_label_sen.shape[0]
    print('repeat dim {}'.format(repdim))
    
    testM = np.repeat(pred_sen_M[:, :, np.newaxis], repdim, axis=2)
    testM2 = testM - label_sen_M.T #find the difference in min and max seniority to each labeled user
    testM3 = np.abs(testM2).sum(axis = 1) #take the abs and sum across both min and max
    id_list_test = np.argmin(testM3, axis = 1)
    
    
    print("id_list length {}".format(len(id_list_test)))
    
    return id_list_test