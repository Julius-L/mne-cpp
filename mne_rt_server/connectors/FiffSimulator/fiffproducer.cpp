//=============================================================================================================
/**
* @file     fiffproducer.cpp
* @author   Christoph Dinh <chdinh@nmr.mgh.harvard.edu>;
*           Matti Hamalainen <msh@nmr.mgh.harvard.edu>
* @version  1.0
* @date     July, 2012
*
* @section  LICENSE
*
* Copyright (C) 2012, Christoph Dinh and Matti Hamalainen. All rights reserved.
*
* Redistribution and use in source and binary forms, with or without modification, are permitted provided that
* the following conditions are met:
*     * Redistributions of source code must retain the above copyright notice, this list of conditions and the
*       following disclaimer.
*     * Redistributions in binary form must reproduce the above copyright notice, this list of conditions and
*       the following disclaimer in the documentation and/or other materials provided with the distribution.
*     * Neither the name of the Massachusetts General Hospital nor the names of its contributors may be used
*       to endorse or promote products derived from this software without specific prior written permission.
*
* THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED
* WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A
* PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL MASSACHUSETTS GENERAL HOSPITAL BE LIABLE FOR ANY DIRECT,
* INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
* PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
* HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING
* NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
* POSSIBILITY OF SUCH DAMAGE.
*
*
* @brief    Contains the implementation of the DataProducer Class.
*
*/

//*************************************************************************************************************
//=============================================================================================================
// INCLUDES
//=============================================================================================================

#include "fiffproducer.h"
#include "fiffsimulator.h"


//*************************************************************************************************************
//=============================================================================================================
// Qt INCLUDES
//=============================================================================================================

#include <QDebug>


//*************************************************************************************************************
//=============================================================================================================
// USED NAMESPACES
//=============================================================================================================

using namespace FiffSimulatorPlugin;


//*************************************************************************************************************
//=============================================================================================================
// DEFINE MEMBER METHODS
//=============================================================================================================

FiffProducer::FiffProducer(FiffSimulator* p_pFiffSimulator)
: m_pFiffSimulator(p_pFiffSimulator)
, m_bIsRunning(false)
{

}


//*************************************************************************************************************

FiffProducer::~FiffProducer()
{

}


//*************************************************************************************************************

void FiffProducer::stop()
{
    m_bIsRunning = false;
    QThread::wait();
}


//*************************************************************************************************************

void FiffProducer::run()
{
    m_bIsRunning = true;

    // reopen file in this thread
    QFile* t_pFile = new QFile(m_pFiffSimulator->m_pRawInfo->info->filename);
    FiffStream* p_pStream = new FiffStream(t_pFile);
    m_pFiffSimulator->m_pRawInfo->file = p_pStream;

    //
    //   Set up the reading parameters
    //
    fiff_int_t from = m_pFiffSimulator->m_pRawInfo->first_samp;
    fiff_int_t to = m_pFiffSimulator->m_pRawInfo->last_samp;
//    float quantum_sec = (float)uiSamplePeriod/1000000.0f; //read and write in 10 sec junks
    fiff_int_t quantum = m_pFiffSimulator->getBufferSampleSize();//ceil(quantum_sec*m_pFiffSimulator->m_pRawInfo->info->sfreq);

    qDebug() << "quantum " << quantum;


    //
    //   To read the whole file at once set
    //
    //quantum     = to - from + 1;
    //
    //
    //   Read and write all the data
    //
    bool first_buffer = true;

    fiff_int_t first, last;
    MatrixXd* data = NULL;
    MatrixXd* times = NULL;

    first = from;

    qint32 nchan = m_pFiffSimulator->m_pRawInfo->info->nchan;

    MatrixXd cals(1,nchan);

    SparseMatrix<double> inv_calsMat(nchan, nchan);

    for(qint32 i = 0; i < nchan; ++i)
        inv_calsMat.insert(i, i) = 1.0f/m_pFiffSimulator->m_pRawInfo->info->chs[i].cal;

    //Not good cause production time is not accurate
    //loading and thread sleep is longer than thread sleep time - better to have a extra loading thread
    // ToDo restructure this producer as laoding buffer --> and thread sleep to simulator buffer
    while(first < to)//m_bIsRunning)
    {
        last = first+quantum-1;
        if (last > to)
        {
            last = to;
        }

        if (!m_pFiffSimulator->m_pRawInfo->read_raw_segment(data,times,first,last))
        {
            printf("error during read_raw_segment\n");
        }

        MatrixXf tmp = (inv_calsMat*(*data)).cast<float>();


        m_pFiffSimulator->m_pRawMatrixBuffer->push(&tmp);

        first+=quantum;
    }

    // close datastream in this thread
    delete m_pFiffSimulator->m_pRawInfo->file;
    m_pFiffSimulator->m_pRawInfo->file = NULL;
}